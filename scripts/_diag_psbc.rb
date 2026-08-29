require 'bundler/setup'
require_relative '../models'
require_relative '../services/dividend_syncer'
require 'yaml'

CODE = '601658'
stock = Stock.where(asset_type: 'stock', code: CODE).first

puts "=== #{stock.code} #{stock.name}  price=#{stock.current_price}"
puts "stocks 表字段:"
puts "  dividend_yield=#{stock.dividend_yield.inspect}"
puts "  avg_dividend_yield_3y=#{stock.avg_dividend_yield_3y.inspect}"
puts "  min_dividend_yield_3y=#{stock.min_dividend_yield_3y.inspect}"
puts "  consecutive=#{stock.consecutive_dividend_years.inspect}"
puts "  dps_year=#{stock.dividend_cash_per_share_year.inspect}  dps_latest=#{stock.dividend_cash_per_share_latest_year.inspect}"
puts
syn = DividendSyncer.new(scope: Stock.none, sleep_range: nil, force: false)
per_year = syn.send(:per_year_cash, stock)
puts "per_year (只统计 12-31): #{per_year.sort.inspect}"
puts

# 模拟 gt3_pages 的 latest_year + 3y 选择逻辑
latest_div = stock.dividends.order(report_date: :desc).first
latest_year_end =
  stock.dividends
    .where("extract(month from report_date) = 12 and extract(day from report_date) = 31")
    .order(report_date: :desc)
    .limit(1)
    .pluck(:report_date)
    .first
latest_year = latest_year_end ? latest_year_end.year : (latest_div ? latest_div.report_date.year : nil)
puts "latest_div report_date=#{latest_div&.report_date}  cash=#{latest_div&.cash_dividend}"
puts "latest_year_end=#{latest_year_end.inspect}  => latest_year=#{latest_year.inspect}"

if latest_year
  y2 = latest_year - 2
  y1 = latest_year - 1
  y0 = latest_year
  dps2 = per_year[y2].to_f
  dps1 = per_year[y1].to_f
  dps0 = per_year[y0].to_f
  puts
  puts "取 3 年 dps: #{y2}=#{dps2}  #{y1}=#{dps1}  #{y0}=#{dps0}"
  cp = stock.current_price.to_f
  yields = [dps2, dps1, dps0].map { |dps| (dps / cp * 100.0) }
  puts "yield 分解: #{y2}=#{sprintf('%.4f%%', yields[0])}  #{y1}=#{sprintf('%.4f%%', yields[1])}  #{y0}=#{sprintf('%.4f%%', yields[2])}"
  puts "avg=#{sprintf('%.4f%%', yields.sum/3)}  min=#{sprintf('%.4f%%', yields.min)}"
end

puts
puts "=== dividends 最近 12 条明细（含中报）==="
attrs = %i[report_date cash_dividend bonus_issue rights_issue notice_date plan_description].select { |a| Dividend.column_names.include?(a.to_s) }
stock.dividends.order(report_date: :desc).limit(12).each do |d|
  parts = attrs.map { |a| "#{a}=#{d.send(a).inspect}" }
  puts "  " + parts.join("  ")
end
