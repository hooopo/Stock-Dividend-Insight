require 'yaml'
d = YAML.load_file('docs/gt3/data.yml')
s0 = d[:stocks].detect { |s| s[:code] == '601985' }
puts "601985 keys: " + s0.keys.sort.inspect
puts
s1 = d[:stocks].detect { |s| s[:code] == '601985' }
[:buy_price_5, :buy_price_6, :buy_price_7, :first_price, :add_price, :heavy_price, :first_yield, :add_yield, :heavy_yield].each do |k|
  puts "  #{k} = #{s1[k].inspect}"
end
