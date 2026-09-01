require 'bundler/setup'
require_relative '../models'
require_relative '../services/dividend_syncer'
require_relative '../services/quote_snapshot_syncer'

codes = %w[000807 601600 600362 000878 601899 603993]
names = { '000807' => '云铝股份', '601600' => '中国铝业', '600362' => '江西铜业',
          '000878' => '云南铜业', '601899' => '紫金矿业', '603993' => '洛阳钼业' }

codes.each do |c|
  next if Stock.where(asset_type: 'stock', code: c).exists?
  prefix = c.start_with?('6') ? '1' : '0'
  Stock.create!(
    code: c, name: names[c], asset_type: 'stock',
    market_id: c.start_with?('6') ? 1 : 0,
    secid: "#{c}.#{prefix}"
  )
  puts "建骨架: #{c} #{names[c]}"
end

scope = Stock.where(asset_type: 'stock', code: codes)

qsyn = QuoteSnapshotSyncer.new(scope: scope, batch_sleep: 0.1)
qsyn.sync
puts '--- quotes synced ---'

syn = DividendSyncer.new(scope: scope, sleep_range: nil, force: true)
syn.sync
puts '--- dividends synced ---'

scope.order(:code).each do |s|
  per_year = syn.send(:per_year_cash, s)
  recent = per_year.keys.sort.last(5).map { |y| "#{y}:#{format('%.4f', per_year[y])}" }
  puts "#{s.code} #{s.name} CP=#{s.current_price} dy=#{s.dividend_yield.to_f.round(3)}% avg3y=#{s.avg_dividend_yield_3y.to_f.round(3)}% min3y=#{s.min_dividend_yield_3y.to_f.round(3)}% consec=#{s.consecutive_dividend_years} payout=#{s.dividend_payout_ratio.to_f.round(2)} recent_DPS=#{recent.join(' ')}"
end
