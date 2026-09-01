require 'yaml'
abort('gt3_pages 失败') unless system('bundle exec ruby scripts/gt3_pages.rb', out: '/tmp/_gt3_metal.out', err: '/tmp/_gt3_metal.out')
puts File.readlines('/tmp/_gt3_metal.out').last(5).join

d = YAML.load_file('docs/gt3/data.yml')
codes = %w[000807 601600 600362 000878 601899 603993]
puts '=' * 160
d[:stocks].select { |s| codes.include? s[:code] }.each do |s|
  f = ->(v, f = '%.2f') { v.nil? ? '空' : format(f, v) }
  dy = s[:dividend_yield].nil? ? '空' : format('%.2f%%', s[:dividend_yield])
  a3 = s[:avg_dividend_yield_3y] ? format('%.2f%%', s[:avg_dividend_yield_3y]) : '空'
  m3 = s[:min_dividend_yield_3y] ? format('%.2f%%', s[:min_dividend_yield_3y]) : '空'
  puts "#{s[:code]} #{s[:name].ljust(6)} wl=#{s[:is_whitelist]} 大=#{s[:whitelist_big_category].to_s.ljust(4)} 小=#{s[:whitelist_sub_category].to_s.ljust(4)} 现价#{format('%.2f', s[:current_price]).ljust(6)}  新=#{dy.ljust(8)} 均=#{a3.ljust(8)} 低=#{m3.ljust(8)} 连续#{s[:consecutive_dividend_years].to_s.ljust(3)}年"
  puts "        首#{s[:first_yield]}%/加#{s[:add_yield]}%/重#{s[:heavy_yield]}%   阶梯价 首=#{f[s[:buy_price_5], '%.2f']} 加=#{f[s[:buy_price_6], '%.2f']} 重=#{f[s[:buy_price_7], '%.2f']}"
end
puts
puts "白名单总数: #{d[:stocks].count { |x| x[:is_whitelist] }} / #{d[:stocks].size}"
