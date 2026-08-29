require 'yaml'
d = YAML.load_file('docs/gt3/data.yml')
codes = %w[601658 601398 601939 601288 601988 601328]
puts '邮储+六大行最终页面数据（含首仓/加仓/重仓价）:'
puts '-' * 140
d[:stocks].select { |s| codes.include? s[:code] }.each do |s|
  dy = s[:dividend_yield] ? format('%.2f%%', s[:dividend_yield]) : s[:dividend_yield].inspect
  a3 = s[:avg_dividend_yield_3y] ? format('%.2f%%', s[:avg_dividend_yield_3y]) : '空'
  m3 = s[:min_dividend_yield_3y] ? format('%.2f%%', s[:min_dividend_yield_3y]) : '空'
  b5 = s[:buy_price_5] ? format('%.2f', s[:buy_price_5]) : '空'
  b6 = s[:buy_price_6] ? format('%.2f', s[:buy_price_6]) : '空'
  b7 = s[:buy_price_7] ? format('%.2f', s[:buy_price_7]) : '空'
  fy = s[:first_yield] ? format('%.1f%%', s[:first_yield]) : '空'
  ay = s[:add_yield] ? format('%.1f%%', s[:add_yield]) : '空'
  hy = s[:heavy_yield] ? format('%.1f%%', s[:heavy_yield]) : '空'
  puts "#{s[:code].ljust(6)} #{s[:name].ljust(8)} 现价=#{sprintf('%.2f',s[:current_price]).ljust(6)} 新=#{dy.ljust(8)} 均=#{a3.ljust(8)} 低=#{m3.ljust(8)} 连续#{s[:consecutive_dividend_years].to_s.ljust(3)}年"
  puts "        目标息率: First=#{fy} Add=#{ay} Heavy=#{hy}   阶梯价:首仓=#{b5}  加仓=#{b6}  重仓=#{b7}"
end
