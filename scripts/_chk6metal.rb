require 'bundler/setup'
require_relative '../models'
require 'yaml'

data = [
  { code: '000807', name: '云铝股份', cats: %w[有色金属 铝 周期] },
  { code: '601600', name: '中国铝业', cats: %w[有色金属 铝 周期] },
  { code: '600362', name: '江西铜业', cats: %w[有色金属 铜 周期] },
  { code: '000878', name: '云南铜业', cats: %w[有色金属 铜 周期] },
  { code: '601899', name: '紫金矿业', cats: %w[有色金属 黄金 周期] },
  { code: '603993', name: '洛阳钼业', cats: %w[有色金属 小金属 周期] },
]

yml_in = YAML.load_file('stocks-dividend-gt3.yml')
existing = (yml_in.is_a?(Hash) ? (yml_in['stocks'] || []) : (yml_in || [])).dup.to_h { |r| [r['code'].to_s.rjust(6, '0'), r] }
puts "YAML 现有 #{existing.size} 条"

data.each do |row|
  c = row[:code]
  db_s = Stock.where(asset_type: 'stock', code: c).first
  puts "#{c} #{row[:name]}  YAML:#{existing.key?(c) ? '有' : '无'}  DB:#{db_s ? '有' : '无'}  DB cp=#{db_s&.current_price} dy=#{db_s&.dividend_yield.to_f.round(3)} avg3y=#{db_s&.avg_dividend_yield_3y.to_f.round(3)} min3y=#{db_s&.min_dividend_yield_3y.to_f.round(3)} consec=#{db_s&.consecutive_dividend_years}"
end
