require 'bundler/setup'
require_relative '../models'
require 'yaml'

ROOT_DIR = File.expand_path('..', __dir__)
yml = YAML.load_file(File.join(ROOT_DIR, 'stocks-dividend-gt3.yml'))
list = yml.is_a?(Hash) ? (yml['stocks'] || []) : (yml || [])
codes = list.filter_map do |row|
  code = row['code'].to_s.strip.rjust(6, '0')
  code.match?(/^\d{6}$/) ? code : nil
end.uniq

stocks = Stock.where(asset_type: 'stock', code: codes).to_a

bad = []
stocks.each do |s|
  dy = s.dividend_yield.to_f
  m3 = s.min_dividend_yield_3y.to_f
  a3 = s.avg_dividend_yield_3y.to_f
  next unless a3 > 0 && m3 > 0

  suspicious = false
  reasons = []
  if dy <= 0.05
    suspicious = true
    reasons << "DY_ZERO_OR_NEAR_ZERO=#{sprintf('%.4f',dy)}"
  end
  if m3 > 0 && dy < m3 * 0.7
    suspicious = true
    reasons << "DY_TOO_LOW_BELOW_MIN_70PCT: dy=#{sprintf('%.3f',dy)} vs min3y=#{sprintf('%.3f',m3)}"
  end
  if a3 > 0 && dy < a3 * 0.6
    suspicious = true
    reasons << "DY_TOO_LOW_BELOW_AVG_60PCT: dy=#{sprintf('%.3f',dy)} vs avg3y=#{sprintf('%.3f',a3)}"
  end
  bad << [s.code, s.name, s.current_price, dy, a3, m3, s.dividend_cash_per_share_year, s.dividend_cash_per_share_latest_year, reasons.join(' | ')] if suspicious
end

puts "扫描 166 只，发现 #{bad.size} 只 dividend_yield 异常（疑似 TTM 抓取失败导致回退脏值）:"
puts '-' * 150
puts "%-6s %-10s %-7s %-9s %-9s %-9s %-6s %-9s %s" % %w[code name price dy avg3y min3y dpsY dpsLat reason]
bad.first(40).each { |r| puts "%-6s %-10s %-7s %-9s %-9s %-9s %-6s %-9s %s" % [r[0],r[1],sprintf('%.2f',r[2].to_f), sprintf('%.3f',r[3]),sprintf('%.3f',r[4]),sprintf('%.3f',r[5]),r[6].to_s,sprintf('%.3f',r[7].to_f),r[8]] }
