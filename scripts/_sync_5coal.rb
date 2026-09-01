require 'bundler/setup'
require_relative '../models'
require_relative '../services/dividend_syncer'
require_relative '../services/quote_snapshot_syncer'
require 'yaml'

ROOT_DIR = File.expand_path('..', __dir__)
yml = YAML.load_file(File.join(ROOT_DIR, 'stocks-dividend-gt3.yml'))
list = yml.is_a?(Hash) ? (yml['stocks'] || []) : (yml || [])
codes_from_yml =
  list.filter_map do |row|
    code = row['code'].to_s.strip.rjust(6, '0')
    code.match?(/^\d{6}$/) ? code : nil
  end.uniq

coal_codes = %w[601088 601225 600188 601001 600971]
miss = coal_codes.reject { |c| Stock.where(asset_type: 'stock', code: c).exists? }

if miss.any?
  puts "兖矿能源 600188 / 恒源煤电 600971 需先入库基本行情和行业，用QuoteSnapshotSyncer一次性拉取..."
  YAML.load_file(File.join(ROOT_DIR, 'stocks-dividend-gt3.yml'))
  all_rows = (yml.is_a?(Hash) ? (yml['stocks'] || []) : (yml || []))
  entries = all_rows.filter_map do |r|
    c = r['code'].to_s.strip.rjust(6, '0')
    coal_codes.include?(c) ? { code: c, name: r['name'].to_s } : nil
  end
  entries.each do |e|
    next if Stock.where(asset_type: 'stock', code: e[:code]).exists?
    market_id = e[:code].start_with?('6') ? 1 : 0
    prefix = e[:code].start_with?('6') ? '1' : '0'
    secid = "#{e[:code]}.#{prefix}"
    Stock.create!(
      code: e[:code],
      name: e[:name],
      asset_type: 'stock',
      market_id: market_id,
      secid: secid
    )
    puts "插入 stock 骨架: #{e[:code]} #{e[:name]} market_id=#{market_id} secid=#{secid}"
  end
end

stocks = Stock.where(asset_type: 'stock', code: coal_codes).order(:code).to_a

qsyn = QuoteSnapshotSyncer.new(scope: Stock.where(asset_type: 'stock', code: coal_codes), batch_sleep: 0.1)
qsyn.sync

syn = DividendSyncer.new(scope: Stock.where(asset_type: 'stock', code: coal_codes), sleep_range: nil, force: true)
syn.sync

stocks.map(&:reload).each do |s|
  per_year = syn.send(:per_year_cash, s)
  positive = per_year.select { |_, v| v.to_f > 0 }.keys.sort.last(5).map { |y| "#{y}:#{per_year[y].round(4)}" }
  puts "#{s.code} #{s.name} CP=#{s.current_price}  dy=#{s.dividend_yield.to_f.round(3)}%  avg=#{s.avg_dividend_yield_3y.to_f.round(3)}%  min=#{s.min_dividend_yield_3y.to_f.round(3)}%  consec=#{s.consecutive_dividend_years}  per_year=#{positive.join(' ')}"
end
