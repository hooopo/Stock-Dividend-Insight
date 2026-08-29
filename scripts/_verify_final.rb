require 'yaml'
d = YAML.load_file('docs/gt3/data.yml')
codes = %w[601985 000088 000429 600642 600012 600519 600025 002128 600886 601000]

puts "白名单总数: #{d[:stocks].size}"
d[:stocks].select { |s| codes.include? s[:code] }.each do |s|
  dy = s[:dividend_yield] ? format('%.2f%%', s[:dividend_yield]) : s[:dividend_yield].inspect
  a3 = s[:avg_dividend_yield_3y] ? format('%.2f%%', s[:avg_dividend_yield_3y]) : '空'
  m3 = s[:min_dividend_yield_3y] ? format('%.2f%%', s[:min_dividend_yield_3y]) : '空'
  puts "#{s[:code].ljust(6)} #{s[:name].ljust(8)} 新=#{dy.ljust(8)} 均=#{a3.ljust(8)} 低=#{m3.ljust(8)} 连续#{s[:consecutive_dividend_years]}年  ladder:First=#{s[:first_price]} Add=#{s[:add_price]} Heavy=#{s[:heavy_price]}"
end

puts
puts '--- 数据概览 ---'
dy0 = d[:stocks].count { |s| s[:dividend_yield].nil? || s[:dividend_yield] == 0.0 }
avg0 = d[:stocks].count { |s| s[:avg_dividend_yield_3y].nil? }
puts "股息率0/nil: #{dy0}/#{d[:stocks].size}   3年均为空: #{avg0}/#{d[:stocks].size}"
puts '剩下显示空缺的股票（真实三年数据不足，非锚点bug）:'
d[:stocks].select { |s| s[:dividend_yield].nil? || s[:avg_dividend_yield_3y].nil? }.each do |s|
  puts "  #{s[:code]} #{s[:name]}  dy=#{s[:dividend_yield].inspect} avg=#{s[:avg_dividend_yield_3y].inspect} min=#{s[:min_dividend_yield_3y].inspect} consec=#{s[:consecutive_dividend_years]}"
end
