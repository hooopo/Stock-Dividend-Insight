require 'faraday'
require 'faraday/retry'
require 'json'
require 'date'

class DividendSyncer
  def initialize(scope: Stock.all, sleep_range: (1.0..2.0), force: false)
    @scope = scope
    @sleep_range = sleep_range
    @force = force
  end

  def sync
    @scope.find_each do |stock|
      puts "Syncing dividends for #{stock.name} (#{stock.secid})..."
      begin
        Dividend.where(stock_id: stock.id).delete_all if @force
        fetch_and_save_dividends(stock)
      rescue Faraday::Error, JSON::ParserError => e
        puts "Error syncing dividends for #{stock.name}: #{e.message}"
      end
      sleep(rand(@sleep_range)) if @sleep_range
    end
  end

  private

  def fetch_and_save_dividends(stock)
    url = "https://datacenter-web.eastmoney.com/api/data/get"
    params = {
      type: "RPT_LICO_FN_CPD",
      sty: "ALL",
      filter: "(SECURITY_CODE=\"#{stock.code}\")",
      p: 1,
      ps: 50
    }

    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'application/json'
    }

    conn = Faraday.new(url: url) do |f|
      f.request :url_encoded
      f.request :retry, max: 3, interval: 0.05,
                       interval_randomness: 0.5, backoff_factor: 2,
                       exceptions: [Faraday::Error, JSON::ParserError]
      f.adapter Faraday.default_adapter
    end

    response = conn.get('', params, headers)
    return unless response.success?

    data = JSON.parse(response.body) rescue nil
    results = data.dig('result', 'data') if data
    
    if results.nil? || results.empty?
      puts "No dividend data in response for #{stock.name}: #{response.body[0..200]}"
      return
    end

    records_created = 0
    results.each do |item|
      report_date = Date.parse(item['REPORTDATE']) rescue nil
      next unless report_date

      description = item['ASSIGNDSCRPT']
      if description.nil?
        next
      end

      base = 10.0
      if description =~ /(\d+)(?:派|送|转)/
        base = $1.to_f
      end

      cash = 0.0
      bonus = 0.0
      rights = 0.0

      if base > 0
        cash = $1.to_f / base if description =~ /派\s*([\d\.]+)\s*元/
        bonus = $1.to_f / base if description =~ /送\s*([\d\.]+)\s*股/
        rights = $1.to_f / base if description =~ /转\s*([\d\.]+)\s*股/
      end

      div = Dividend.find_or_initialize_by(stock_id: stock.id, report_date: report_date)
      div.notice_date = Date.parse(item['NOTICE_DATE']) rescue nil
      div.plan_description = description
      div.cash_dividend = cash.finite? ? cash : 0
      div.bonus_issue = bonus.finite? ? bonus : 0
      div.rights_issue = rights.finite? ? rights : 0
      
      yield_val = item['ZXGXL'].to_f
      div.dividend_yield = yield_val.finite? ? yield_val : nil
      
      if div.changed?
        div.save!
        records_created += 1
      end
    end
    latest_price = stock.current_price || stock.price_histories.order(date: :desc).limit(1).pluck(:close).first
    if latest_price && latest_price.to_f > 0
      latest_dividend = stock.dividends.order(report_date: :desc).first
      if latest_dividend
        latest_year = latest_dividend.report_date.year
        year_sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend)
        stock.dividend_yield = year_sum.to_f > 0 ? (year_sum.to_f / latest_price.to_f) * 100.0 : 0.0
      else
        stock.dividend_yield = 0.0
      end
      stock.save! if stock.changed?
    end

    puts "Saved #{records_created} dividend records for #{stock.name}."
  end
end
