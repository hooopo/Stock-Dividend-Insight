require 'yaml'
d = YAML.load_file('docs/gt3/data.yml')
s = d[:stocks].detect { |x| x[:code] == '601088' }
puts "#{s[:code]} #{s[:name]} wl=#{s[:is_whitelist]} big=#{s[:whitelist_big_category]} sub=#{s[:whitelist_sub_category]} 现价#{format('%.2f', s[:current_price])}"
puts "  新#{format('%.2f%%', s[:dividend_yield])} 均#{s[:avg_dividend_yield_3y] ? format('%.2f%%', s[:avg_dividend_yield_3y]) : '空'} 低#{s[:min_dividend_yield_3y] ? format('%.2f%%', s[:min_dividend_yield_3y]) : '空'} 连续#{s[:consecutive_dividend_years]}年"
puts "  目标息率 首#{s[:first_yield]}% 加#{s[:add_yield]}% 重#{s[:heavy_yield]}%"
puts "  阶梯价 首#{format('%.2f', s[:buy_price_5].to_f)} 加#{format('%.2f', s[:buy_price_6].to_f)} 重#{format('%.2f', s[:buy_price_7].to_f)}"
puts "白名单总计: #{d[:stocks].count { |x| x[:is_whitelist] }} / #{d[:stocks].size}"
