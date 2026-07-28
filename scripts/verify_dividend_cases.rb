require 'bundler/setup'
require 'date'
require 'faraday'
require 'faraday/net_http_persistent'
require 'json'

require_relative '../models'

def em_code(stock)
  market_prefix = stock.market_id.to_i == 1 ? 'SH' : 'SZ'
  "#{market_prefix}#{stock.code}"
end

def parse_date(value)
  return nil if value.nil?
  s = value.to_s.strip
  return nil if s.empty?
  Date.parse(s) rescue nil
end

def parse_cash_per_share(description)
  return 0.0 if description.nil?
  s = description.to_s
  base = 10.0
  if s =~ /(\d+(?:\.\d+)?)(?:派|送|转)/
    base = $1.to_f
  end
  return 0.0 unless base.positive?
  return 0.0 unless s =~ /派\s*([\d\.]+)\s*元/
  ($1.to_f / base)
end

def fetch_pageajax_events(conn, stock)
  headers = {
    'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept' => 'application/json',
    'X-Requested-With' => 'XMLHttpRequest'
  }
  response = conn.get('/BonusFinancing/PageAjax', { code: em_code(stock) }, headers)
  return [] unless response.success?

  data = JSON.parse(response.body) rescue nil
  rows = data && data['fhyx'].is_a?(Array) ? data['fhyx'] : []

  seen = {}
  rows.filter_map do |item|
    progress = item['ASSIGN_PROGRESS'].to_s
    next unless progress.include?('实施')

    ex_date = parse_date(item['EX_DIVIDEND_DATE'])
    next unless ex_date

    desc = item['IMPL_PLAN_PROFILE'].to_s.strip
    next if desc.empty?

    cash = parse_cash_per_share(desc)
    next unless cash.positive?

    key = [ex_date.to_s, format('%.6f', cash), desc].join('|')
    next if seen[key]
    seen[key] = true

    { ex_dividend_date: ex_date, cash_dividend: cash, plan_description: desc }
  end
end

def ttm_cash(events, base_date: Date.today)
  cutoff = base_date - 365
  events.sum do |e|
    d = e[:ex_dividend_date]
    next 0.0 unless d && d > cutoff && d <= base_date
    e[:cash_dividend].to_f
  end
end

def year_cash_from_db(stock)
  latest = stock.dividends.order(report_date: :desc).first
  return [nil, 0.0] unless latest
  y = latest.report_date.year
  sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', y).sum(:cash_dividend).to_f
  [y, sum]
end

codes = %w[000538 600219 601169 600642 600350]

conn =
  Faraday.new(url: 'https://emweb.eastmoney.com') do |f|
    f.request :url_encoded
    f.adapter :net_http_persistent
  end

rows =
  codes.map do |code|
    stock = Stock.find_by(code: code)
    next({ code: code, error: 'missing_stock' }) unless stock

    events = fetch_pageajax_events(conn, stock)
    ttm = ttm_cash(events, base_date: Date.today)
    y, ysum = year_cash_from_db(stock)

    price = (stock.current_price || stock.price_histories.order(date: :desc).limit(1).pluck(:close).first).to_f
    pageajax_yield = price.positive? ? (ttm / price) * 100.0 : nil
    year_yield = price.positive? ? (ysum / price) * 100.0 : nil

    {
      code: code,
      name: stock.name,
      price: price,
      db_dividend_yield: stock.dividend_yield&.to_f,
      db_expected_dividend_yield: stock.expected_dividend_yield&.to_f,
      pageajax_ttm_cash: ttm.round(6),
      pageajax_ttm_yield: pageajax_yield&.round(4),
      db_latest_year: y,
      db_latest_year_cash: ysum.round(6),
      db_latest_year_yield: year_yield&.round(4),
      pageajax_recent: events.sort_by { |e| e[:ex_dividend_date] }.last(4).map { |e| [e[:ex_dividend_date].to_s, e[:cash_dividend].round(6), e[:plan_description]] }
    }
  end.compact

puts JSON.pretty_generate(rows)
