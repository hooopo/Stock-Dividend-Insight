require 'bundler/setup'
require_relative '../models'
require_relative '../services/dividend_syncer'
require 'yaml'

ROOT_DIR = File.expand_path('..', __dir__)
WHITELIST_YML = File.join(ROOT_DIR, 'stocks-dividend-gt3.yml')
yml = YAML.load_file(WHITELIST_YML)
list = yml.is_a?(Hash) ? (yml['stocks'] || []) : (yml || [])
codes =
  list.filter_map do |row|
    code = row['code'].to_s.strip.rjust(6, '0')
    code.match?(/^\d{6}$/) ? code : nil
  end.uniq

stocks = Stock.where(asset_type: 'stock', code: codes).to_a
puts "白名单: #{codes.size} 只, DB匹配: #{stocks.size} 只"

def stats(tag, stocks)
  bad_yield = stocks.count { |s| s.dividend_yield.nil? || s.dividend_yield == 0.0 }
  nil_avg = stocks.count { |s| s.avg_dividend_yield_3y.nil? }
  nil_min = stocks.count { |s| s.min_dividend_yield_3y.nil? }
  consec_nil = stocks.count { |s| s.consecutive_dividend_years.nil? }
  puts "[#{tag}] yield=0/nil=#{bad_yield}/#{stocks.size}  avg3y=nil=#{nil_avg}  min3y=nil=#{nil_min}  consec=nil=#{consec_nil}"
end

stocks.each(&:reload)
stats('BEFORE', stocks)

headers = { 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' }
syn_dummy = DividendSyncer.new(scope: Stock.none, sleep_range: nil, force: false)

SAMPLE_CODES = %w[601658 601398 601939 601288 601988 601328 601985 000088 000429 600642 600519 600012 600025 600886 601000]
before_snapshots = {}
stocks.each do |s|
  before_snapshots[s.code] = {
    dy: s.dividend_yield, avg3y: s.avg_dividend_yield_3y, min3y: s.min_dividend_yield_3y,
    consec: s.consecutive_dividend_years, dps_year: s.dividend_cash_per_share_year,
    dps_latest: s.dividend_cash_per_share_latest_year
  }
end

updated = 0
stocks.each_with_index do |stock, i|
  stock.reload
  per_year = syn_dummy.send(:per_year_cash, stock)
  consecutive = syn_dummy.send(:calc_consecutive_dividend_years, per_year)
  stock.consecutive_dividend_years = consecutive if stock.has_attribute?(:consecutive_dividend_years)

  latest_dividend = stock.dividends.order(report_date: :desc).first
  latest_price = stock.current_price || stock.price_histories.order(date: :desc).limit(1).pluck(:close).first

  if latest_dividend
    positive_years = per_year.select { |_, v| v.to_f > 0.0 }.keys.map(&:to_i)
    current_year = Date.today.year
    latest_year = nil
    if positive_years.any?
      latest_year = positive_years.max
      if latest_year == current_year
        prev = positive_years.sort[-2]
        latest_year = prev if prev
      end
    end
    if latest_year.nil?
      fallback_d = latest_dividend.report_date
      latest_year = fallback_d.year
      latest_year = latest_year - 1 if fallback_d.month <= 6
    end
    year_sum = latest_year ? per_year[latest_year].to_f : 0.0

    stock.dividend_cash_per_share_year = latest_year if stock.has_attribute?(:dividend_cash_per_share_year)
    stock.dividend_cash_per_share_latest_year = year_sum if stock.has_attribute?(:dividend_cash_per_share_latest_year)

    ttm_cash = nil
    if latest_price && latest_price.to_f > 0
      ttm_cash = syn_dummy.send(:ttm_cash_from_bonus, stock, base_date: Date.today, headers: headers) rescue nil
    end

    year_cash = year_sum.positive? ? year_sum : nil
    ttm_val  = ttm_cash&.positive? ? ttm_cash : nil
    if year_cash && ttm_val
      cash_for_yield = [year_cash.to_f, ttm_val.to_f].max
    elsif year_cash
      cash_for_yield = year_cash
    elsif ttm_val
      cash_for_yield = ttm_val
    else
      cash_for_yield = nil
    end
    if latest_price && latest_price.to_f > 0 && cash_for_yield
      stock.dividend_yield = (cash_for_yield.to_f / latest_price.to_f) * 100.0
      stock.expected_dividend_yield = stock.dividend_yield if stock.has_attribute?(:expected_dividend_yield)
    else
      stock.dividend_yield = nil
      stock.expected_dividend_yield = 0.0 if stock.has_attribute?(:expected_dividend_yield)
    end

    if stock.has_attribute?(:avg_dividend_yield_3y) && latest_year
      y2 = latest_year - 2
      y1 = latest_year - 1
      y0 = latest_year
      dps2 = per_year[y2].to_f
      dps1 = per_year[y1].to_f
      dps0 = per_year[y0].to_f
      if latest_price && latest_price.to_f > 0 && dps2 > 0 && dps1 > 0 && dps0 > 0
        yields = [dps2, dps1, dps0].map { |dps| (dps / latest_price.to_f) * 100.0 }
        stock.avg_dividend_yield_3y = yields.sum / 3.0
        stock.min_dividend_yield_3y = yields.min if stock.has_attribute?(:min_dividend_yield_3y)
      else
        stock.avg_dividend_yield_3y = nil
        stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
      end
    elsif stock.has_attribute?(:avg_dividend_yield_3y)
      stock.avg_dividend_yield_3y = nil
      stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
    end
  else
    stock.consecutive_dividend_years = nil if stock.has_attribute?(:consecutive_dividend_years)
    stock.dividend_yield = nil
    stock.dividend_cash_per_share_year = nil if stock.has_attribute?(:dividend_cash_per_share_year)
    stock.dividend_cash_per_share_latest_year = nil if stock.has_attribute?(:dividend_cash_per_share_latest_year)
    stock.avg_dividend_yield_3y = nil if stock.has_attribute?(:avg_dividend_yield_3y)
    stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
    stock.expected_dividend_yield = 0.0 if stock.has_attribute?(:expected_dividend_yield)
  end

  if stock.changed?
    stock.save!
    updated += 1
  end
  sleep 0.12 if (i + 1) % 3 == 0
end

stocks.each(&:reload)
stats('AFTER', stocks)
puts "DB 写入行数: #{updated}"

puts
puts "=== 抽样 10 只改前后对比 ==="
SAMPLE_CODES.each do |c|
  s = stocks.find { |x| x.code == c }
  next unless s
  b = before_snapshots[c]
  puts "#{c} #{s.name}"
  puts "  yield:  #{sprintf('%6s',b[:dy]&.round(2))}  ->  #{sprintf('%-6s',s.dividend_yield&.round(2))}"
  puts "  avg3y:  #{sprintf('%6s',b[:avg3y]&.round(2))}  ->  #{sprintf('%-6s',s.avg_dividend_yield_3y&.round(2))}"
  puts "  min3y:  #{sprintf('%6s',b[:min3y]&.round(2))}  ->  #{sprintf('%-6s',s.min_dividend_yield_3y&.round(2))}"
  puts "  consec: #{sprintf('%6s',b[:consec])}  ->  #{sprintf('%-6s',s.consecutive_dividend_years)}"
  puts "  dps_year:#{sprintf('%6s',b[:dps_year])}  ->  #{sprintf('%-6s',s.dividend_cash_per_share_year)}  dps_latest:#{sprintf('%6s',b[:dps_latest]&.round(3))} -> #{s.dividend_cash_per_share_latest_year&.round(3)}"
end
