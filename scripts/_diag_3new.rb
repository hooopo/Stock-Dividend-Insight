require 'bundler/setup'
require_relative '../models'
require_relative '../services/dividend_syncer'
require 'yaml'

codes = %w[600674 601398 601728]
headers = { 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36' }
syn = DividendSyncer.new(scope: Stock.none, sleep_range: nil, force: false)

stocks = Stock.where(asset_type: 'stock', code: codes).to_a

d = YAML.load_file('docs/gt3/data.yml')
yml_by_code = d[:stocks].index_by { |s| s[:code] }

stocks.each do |s|
  per_year = syn.send(:per_year_cash, s)
  latest_div = s.dividends.order(report_date: :desc).first
  y = yml_by_code[s.code]

  puts "=== #{s.code} #{s.name}  current_price=#{s.current_price}"
  puts "DB stocks.dividend_yield = #{s.dividend_yield.inspect}"
  puts "DB stocks.avg_dividend_yield_3y = #{s.avg_dividend_yield_3y.inspect}"
  puts "DB stocks.min_dividend_yield_3y = #{s.min_dividend_yield_3y.inspect}"
  puts "DB stocks.dividend_cash_per_share_year = #{s.dividend_cash_per_share_year.inspect}"
  puts "DB stocks.dividend_cash_per_share_latest_year = #{s.dividend_cash_per_share_latest_year.inspect}"
  puts "data.yml dividend_yield = #{y[:dividend_yield].inspect}"
  puts "data.yml avg3y = #{y[:avg_dividend_yield_3y].inspect}"
  puts "data.yml min3y = #{y[:min_dividend_yield_3y].inspect}"
  puts "latest_div report_date=#{latest_div&.report_date} cash=#{latest_div&.cash_dividend} desc=#{latest_div&.plan_description.inspect}"
  puts "per_year (cash>0): #{per_year.sort.last(6).to_h.inspect}"

  ttm_cash = syn.send(:ttm_cash_from_bonus, s, base_date: Date.today, headers: headers) rescue nil
  evs = syn.send(:fetch_bonus_cash_events, s, headers) rescue []
  cp = s.current_price.to_f
  puts "TTM cash(BonusFinancing) = #{ttm_cash.inspect} -> TTM yield = #{ttm_cash && cp>0 ? (ttm_cash/cp*100).round(3) : nil}"
  puts "Last 5 Bonus events:"
  evs.first(5).each { |e| puts "  ex=#{e[:ex_dividend_date]} cash=#{e[:cash_dividend]} #{e[:plan_description]}" }
  # 兜底重新按最新口径计算一遍
  positive = per_year.select{|k,v| v>0}.keys.map(&:to_i)
  ly = positive.max
  ly = (positive.sort[-2] || ly) if ly == Date.today.year && positive.size>=2
  year_sum = per_year[ly].to_f
  cash_for = ttm_cash&.positive? ? ttm_cash : (year_sum.positive? ? year_sum : nil)
  puts "RECOMPUTE: latest_year=#{ly} year_sum=#{year_sum} cash_for_yield=#{cash_for}"
  puts "  -> yield = #{cash_for && cp>0 ? (cash_for/cp*100).round(3) : nil}"
  if ly
    y0,y1,y2 = per_year[ly].to_f, per_year[ly-1].to_f, per_year[ly-2].to_f
    if y0>0 && y1>0 && y2>0 && cp>0
      ylds = [y0,y1,y2].map{|x| x/cp*100}
      puts "  -> 3y yields=#{ylds.map{|x| x.round(3)}} avg=#{(ylds.sum/3).round(3)} min=#{ylds.min.round(3)}"
    end
  end
  puts
end
