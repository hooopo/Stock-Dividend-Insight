require 'bundler/setup'
require_relative '../models'
require_relative '../services/dividend_syncer'

codes = %w[601985 000088 000429]
stocks = Stock.where(asset_type: 'stock', code: codes).order(:code).to_a

def snapshot(label, stocks)
  puts
  puts '=' * 80
  puts "=== #{label}"
  puts '=' * 80
  stocks.each do |s|
    s.reload
    puts "#{s.code} #{s.name}  price=#{s.current_price}"
    puts "  yield=#{s.dividend_yield.inspect}  avg3y=#{s.avg_dividend_yield_3y.inspect}  min3y=#{s.min_dividend_yield_3y.inspect}"
    puts "  consecutive=#{s.consecutive_dividend_years.inspect}  payout=#{s.dividend_payout_ratio.inspect}"
    puts "  dps_year=#{s.dividend_cash_per_share_year.inspect}  dps_latest=#{s.dividend_cash_per_share_latest_year.inspect}"
    syn = DividendSyncer.new(scope: Stock.where(id: s.id), sleep_range: nil, force: false)
    per_year = syn.send(:per_year_cash, s)
    puts "  per_year (12-31 only): #{per_year.sort.last(6).to_h.inspect}"
    puts
  end
end

snapshot('BEFORE FORCE RESYNC', stocks)

puts
puts '>>> Running DividendSyncer with force=true for 3 stocks...'
syncer = DividendSyncer.new(scope: Stock.where(id: stocks.map(&:id)), sleep_range: (0.2..0.4), force: true)
syncer.sync

snapshot('AFTER FORCE RESYNC', stocks)

puts
puts '>>> TTM detail from BonusFinancing PageAjax:'
stocks.each do |s|
  syn = DividendSyncer.new(scope: Stock.where(id: s.id), sleep_range: nil, force: false)
  headers = { 'User-Agent' => 'Mozilla/5.0' }
  ttm = syn.send(:ttm_cash_from_bonus, s, base_date: Date.today, headers: headers)
  events = syn.send(:fetch_bonus_cash_events, s, headers)
  cp = s.current_price.to_f
  ttm_yield = (ttm && cp > 0) ? (ttm / cp * 100.0) : nil
  puts "#{s.code} #{s.name}  TTM cash=#{ttm.inspect}  TTM yield=#{ttm_yield.inspect}"
  puts "  latest 5 events:"
  events.first(5).each { |e| puts "    ex=#{e[:ex_dividend_date]} cash=#{e[:cash_dividend]} #{e[:plan_description]}" }
  puts
end
