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
puts "白名单配置: #{codes.size} 只; DB 匹配: #{stocks.size} 只"

problematic = []
bad_yield = 0
nil_avg = 0
latest_is_interim = 0

stocks.each do |s|
  syn = DividendSyncer.new(scope: Stock.where(id: s.id), sleep_range: nil, force: false)
  per_year = syn.send(:per_year_cash, s)
  latest_div = s.dividends.order(report_date: :desc).first

  interim = false
  if latest_div
    d = latest_div.report_date
    interim = (d.month != 12 || d.day != 31)
    latest_is_interim += 1 if interim
  end

  bad_yield_flag = (s.dividend_yield.nil? || s.dividend_yield == 0.0)
  avg_nil_flag = s.avg_dividend_yield_3y.nil?

  # 实际有连续三年 12-31 分红，说明肯定应该有均/低
  recent3_exist = (2023..2025).all? { |y| per_year[y].to_f > 0 }

  bad_yield += 1 if bad_yield_flag
  nil_avg += 1 if avg_nil_flag

  if (bad_yield_flag || avg_nil_flag) && (interim || recent3_exist)
    problematic << {
      code: s.code, name: s.name,
      dy: s.dividend_yield, avg3y: s.avg_dividend_yield_3y, min3y: s.min_dividend_yield_3y,
      consec: s.consecutive_dividend_years,
      latest_report: latest_div&.report_date,
      latest_cash: latest_div&.cash_dividend,
      interim: interim,
      per_year_last6: per_year.sort.last(6).to_h,
      recent3_positive: recent3_exist
    }
  end
end

puts
puts "问题扫描摘要:"
puts "  1) 最新一条 report_date 不是 12-31（中报/季报干扰）: #{latest_is_interim}/#{stocks.size}"
puts "  2) dividend_yield=0 或 nil: #{bad_yield}/#{stocks.size}"
puts "  3) avg_dividend_yield_3y=nil: #{nil_avg}/#{stocks.size}"
puts "  疑似有问题需修复: #{problematic.size}/#{stocks.size}"
puts
puts "=== 疑似问题 Top 30（按 latest_report desc）==="
problematic
  .sort_by { |x| [x[:latest_report] ? 1 : 0, x[:latest_report].to_s] }
  .reverse
  .first(30)
  .each do |p|
    flags = []
    flags << "INTERIM_LATEST" if p[:interim]
    flags << "RECENT3_OK_BAD_AVG" if p[:avg3y].nil? && p[:recent3_positive]
    flags << "BAD_YIELD" if p[:dy].nil? || p[:dy] == 0.0
    puts "#{p[:code]} #{p[:name]}  dy=#{p[:dy].inspect} avg3y=#{p[:avg3y].inspect} min3y=#{p[:min3y].inspect} consec=#{p[:consec].inspect}"
    puts "  latest=#{p[:latest_report]} cash=#{p[:latest_cash]}  flags=[#{flags.join(' | ')}]"
    puts "  per_year=#{p[:per_year_last6].inspect}"
  end
