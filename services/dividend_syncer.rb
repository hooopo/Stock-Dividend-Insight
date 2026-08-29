require 'faraday'
require 'faraday/retry'
require 'faraday/net_http_persistent'
require 'json'
require 'date'

class DividendSyncer
  def initialize(scope: Stock.all, sleep_range: (1.0..2.0), force: false)
    @scope = scope
    @sleep_range = sleep_range
    @force = force

    @conn =
      Faraday.new(url: 'https://datacenter-web.eastmoney.com') do |f|
        f.request :url_encoded
        f.request :retry, max: 3, interval: 0.05,
                         interval_randomness: 0.5, backoff_factor: 2,
                         exceptions: [Faraday::Error, JSON::ParserError]
        f.options.timeout = 15
        f.options.open_timeout = 8
        f.adapter :net_http_persistent
      end

    @bonus_conn =
      Faraday.new(url: 'https://emweb.eastmoney.com') do |f|
        f.request :url_encoded
        f.request :retry, max: 3, interval: 0.05,
                         interval_randomness: 0.5, backoff_factor: 2,
                         exceptions: [Faraday::Error, JSON::ParserError]
        f.options.timeout = 15
        f.options.open_timeout = 8
        f.adapter :net_http_persistent
      end
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

  def calc_consecutive_dividend_years(per_year)
    positive_years = per_year.select { |_, v| v.to_f > 0.0 }.keys.map(&:to_i)
    return nil if positive_years.empty?

    y = positive_years.max
    n = 0
    while per_year[y - n].to_f > 0.0
      n += 1
    end
    n > 0 ? n : nil
  end

  def per_year_cash(stock)
    per_year = Hash.new(0.0)
    stock.dividends.pluck(:report_date, :cash_dividend).each do |d, cash|
      next unless d
      next unless d.month == 12 && d.day == 31
      per_year[d.year] += cash.to_f
    end
    per_year
  end

  def fetch_bonus_cash_events(stock, headers)
    response = @bonus_conn.get('/BonusFinancing/PageAjax', { code: em_code(stock) }, headers)
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

  def ttm_cash_from_bonus(stock, base_date:, headers:)
    events = fetch_bonus_cash_events(stock, headers)
    return nil if events.empty?

    cutoff = base_date - 365
    sum =
      events.sum do |e|
        d = e[:ex_dividend_date]
        next 0.0 unless d && d > cutoff && d <= base_date
        e[:cash_dividend].to_f
      end
    sum.positive? ? sum : nil
  end

  def fetch_dividend_rows(stock, headers)
    page = 1
    pages = 1
    rows = []

    while page <= pages
      params = {
        type: 'RPT_LICO_FN_CPD',
        sty: 'ALL',
        filter: "(SECURITY_CODE=\"#{stock.code}\")",
        p: page,
        ps: 200
      }

      response = @conn.get('/api/data/get', params, headers)
      break unless response.success?

      data = JSON.parse(response.body) rescue nil
      result = data && data['result'].is_a?(Hash) ? data['result'] : {}
      page_rows = result['data'].is_a?(Array) ? result['data'] : []
      pages = result['pages'].to_i
      pages = 1 if pages <= 0
      rows.concat(page_rows)
      break if page_rows.empty?

      page += 1
    end

    rows
  end

  def fetch_and_save_dividends(stock)
    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'application/json'
    }
    results = fetch_dividend_rows(stock, headers)
    
    if results.nil? || results.empty?
      puts "No dividend data in response for #{stock.name}"
      unless stock.dividends.exists?
        stock.dividend_yield = nil
        stock.dividend_cash_per_share_year = nil if stock.has_attribute?(:dividend_cash_per_share_year)
        stock.dividend_cash_per_share_latest_year = nil if stock.has_attribute?(:dividend_cash_per_share_latest_year)
        stock.save! if stock.changed?
      end
      return
    end

    records_created = 0
    results.each do |item|
      report_date = Date.parse(item['REPORTDATE']) rescue nil
      next unless report_date

      description = item['ASSIGNDSCRPT']
      next if description.nil? || description.to_s.strip.empty?

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
    latest_dividend = stock.dividends.order(report_date: :desc).first
    per_year = per_year_cash(stock)
    if stock.has_attribute?(:consecutive_dividend_years)
      stock.consecutive_dividend_years = calc_consecutive_dividend_years(per_year)
    end

    if latest_dividend
      latest_year_end =
        stock
          .dividends
          .where("extract(month from report_date) = 12 and extract(day from report_date) = 31")
          .order(report_date: :desc)
          .limit(1)
          .pluck(:report_date)
          .first
      if latest_year_end
        latest_year = latest_year_end.year
      else
        latest_year = latest_dividend.report_date.year
        latest_year = latest_year - 1 if latest_dividend.report_date.month <= 6
      end
      year_sum = per_year[latest_year].to_f

      stock.dividend_cash_per_share_year = latest_year if stock.has_attribute?(:dividend_cash_per_share_year)
      stock.dividend_cash_per_share_latest_year = year_sum if stock.has_attribute?(:dividend_cash_per_share_latest_year)

      ttm_cash = nil
      if latest_price && latest_price.to_f > 0
        ttm_cash = ttm_cash_from_bonus(stock, base_date: Date.today, headers: headers)
      end

      cash_for_yield = ttm_cash&.positive? ? ttm_cash : (year_sum.positive? ? year_sum : nil)
      if latest_price && latest_price.to_f > 0 && cash_for_yield
        stock.dividend_yield = (cash_for_yield.to_f / latest_price.to_f) * 100.0
        stock.expected_dividend_yield = stock.dividend_yield if stock.has_attribute?(:expected_dividend_yield)
      else
        stock.dividend_yield = nil
        stock.expected_dividend_yield = 0.0 if stock.has_attribute?(:expected_dividend_yield)
      end

      if stock.has_attribute?(:avg_dividend_yield_3y)
        y2 = latest_year - 2
        y1 = latest_year - 1
        y0 = latest_year
        dps2 = per_year[y2].to_f
        dps1 = per_year[y1].to_f
        dps0 = per_year[y0].to_f

        if latest_price && latest_price.to_f > 0 && dps2 > 0 && dps1 > 0 && dps0 > 0
          yields = [dps2, dps1, dps0].map { |dps| (dps / latest_price.to_f) * 100.0 }
          stock.avg_dividend_yield_3y = yields.sum / 3.0
          stock.min_dividend_yield_3y = yields.min if stock.has_attribute?(:min_dividend_yield_3y)
        else
          stock.avg_dividend_yield_3y = nil
          stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
        end
      end
    else
      stock.consecutive_dividend_years = nil if stock.has_attribute?(:consecutive_dividend_years)
      stock.dividend_yield = nil
      stock.dividend_cash_per_share_year = nil if stock.has_attribute?(:dividend_cash_per_share_year)
      stock.dividend_cash_per_share_latest_year = nil if stock.has_attribute?(:dividend_cash_per_share_latest_year)
      stock.avg_dividend_yield_3y = nil if stock.has_attribute?(:avg_dividend_yield_3y)
      stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
      stock.expected_dividend_yield = 0.0 if stock.has_attribute?(:expected_dividend_yield)
    end
    stock.save! if stock.changed?

    puts "Saved #{records_created} dividend records for #{stock.name}."
  end
end
