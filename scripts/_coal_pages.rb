require 'yaml'
system('bundle exec ruby scripts/gt3_pages.rb', out: '/tmp/_gt3_coal.out', err: '/tmp/_gt3_coal.out') or abort("gt3_pages 失败: #{$?}")
File.readlines('/tmp/_gt3_coal.out').last(5).each(&:display)
puts '---'

d = YAML.load_file('docs/gt3/data.yml')
codes = %w[601088 601225 600188 601001 600971]
puts "煤炭 5 杰最终 data.yml："
puts '-' * 160
d[:stocks].select { |s| codes.include? s[:code] }.each do |s|
  dy = s[:dividend_yield] ? format('%.2f%%', s[:dividend_yield]) : s[:dividend_yield].inspect
  a3 = s[:avg_dividend_yield_3y] ? format('%.2f%%', s[:avg_dividend_yield_3y]) : '空'
  m3 = s[:min_dividend_yield_3y] ? format('%.2f%%', s[:min_dividend_yield_3y]) : '空'
  b5 = s[:buy_price_5] ? format('%.2f', s[:buy_price_5]) : '空'
  b6 = s[:buy_price_6] ? format('%.2f', s[:buy_price_6]) : '空'
  b7 = s[:buy_price_7] ? format('%.2f', s[:buy_price_7]) : '空'
  puts "#{s[:code]} #{s[:name].ljust(6)} wl=#{s[:is_whitelist]} 大=#{s[:whitelist_big_category].to_s.ljust(4)} 小=#{s[:whitelist_sub_category].to_s.ljust(4)} 现价#{sprintf('%.2f', s[:current_price]).ljust(6)}  新=#{dy.ljust(8)} 均=#{a3.ljust(8)} 低=#{m3.ljust(8)} 连续#{s[:consecutive_dividend_years].to_s.ljust(3)}年"
  puts "        目标息率 #{s[:first_yield]}% / #{s[:add_yield]}% / #{s[:heavy_yield]}%     阶梯价 首=#{b5} 加=#{b6} 重=#{b7}"
end
puts
puts "白名单总数: #{d[:stocks].count { |x| x[:is_whitelist] }} / #{d[:stocks].size}"
