require 'faraday'
require 'faraday/retry'
require 'faraday/net_http_persistent'
require 'json'
require 'date'
require_relative 'dividend_metrics'

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

  def parse_plan_metrics(description)
    base = 10.0
    if description =~ /(\d+(?:\.\d+)?)(?:派|送|转)/
      base = $1.to_f
    end

    cash = 0.0
    bonus = 0.0
    rights = 0.0

    if base > 0
      cash = $1.to_f / base if description =~ /派\s*([\d\.]+)\s*元/
      bonus = $1.to_f / base if description =~ /送\s*([\d\.]+)\s*股?/
      rights = $1.to_f / base if description =~ /转\s*([\d\.]+)\s*股?/
    end

    [cash, bonus, rights]
  end

  def fetch_bonus_history_rows(stock, headers)
    response = @bonus_conn.get('/BonusFinancing/PageAjax', { code: em_code(stock) }, headers)
    return [] unless response.success?

    data = JSON.parse(response.body) rescue nil
    rows = data && data['fhyx'].is_a?(Array) ? data['fhyx'] : []

    rows.filter_map do |item|
      description = item['IMPL_PLAN_PROFILE'].to_s.strip
      progress = item['ASSIGN_PROGRESS'].to_s.strip
      ex_dividend_date = parse_date(item['EX_DIVIDEND_DATE'])
      next if description.empty?
      next unless progress.include?('实施')
      next unless ex_dividend_date && ex_dividend_date <= Date.today

      cash, bonus, rights = parse_plan_metrics(description)
      next if cash <= 0 && bonus <= 0 && rights <= 0

      {
        report_date: ex_dividend_date,
        notice_date: parse_date(item['NOTICE_DATE']),
        ex_dividend_date: ex_dividend_date,
        fiscal_year: ex_dividend_date.year,
        plan_description: description,
        cash_dividend: cash.finite? ? cash : 0.0,
        bonus_issue: bonus.finite? ? bonus : 0.0,
        rights_issue: rights.finite? ? rights : 0.0,
        dividend_yield: nil
      }
    end
  end

  def fetch_report_rows(stock, headers)
    page = 1
    pages = 1
    rows = []

    while page <= pages
      params = {
        reportName: 'RPT_SHAREBONUS_DET',
        columns: 'ALL',
        quoteColumns: '',
        filter: "(SECURITY_CODE=\"#{stock.code}\")",
        pageNumber: page,
        pageSize: 50,
        sortColumns: 'PLAN_NOTICE_DATE',
        sortTypes: -1,
        source: 'WEB',
        client: 'WEB'
      }

      response = @conn.get('/api/data/v1/get', params, headers)
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

    rows.filter_map do |item|
      description = item['IMPL_PLAN_PROFILE'].to_s.strip
      report_date = parse_date(item['REPORT_DATE'])
      ex_dividend_date = parse_date(item['EX_DIVIDEND_DATE'])
      event_date = ex_dividend_date || report_date
      next unless event_date
      next if description.empty?

      cash, bonus, rights = parse_plan_metrics(description)
      next if cash <= 0 && bonus <= 0 && rights <= 0

      raw_yield = item['DIVIDENT_RATIO']
      yield_val = raw_yield.nil? ? nil : raw_yield.to_f * 100.0

      {
        report_date: event_date,
        notice_date: parse_date(item['PLAN_NOTICE_DATE'] || item['NOTICE_DATE']),
        ex_dividend_date: ex_dividend_date,
        fiscal_year: ex_dividend_date&.year || report_date&.year,
        plan_description: description,
        cash_dividend: cash.finite? ? cash : 0.0,
        bonus_issue: bonus.finite? ? bonus : 0.0,
        rights_issue: rights.finite? ? rights : 0.0,
        dividend_yield: yield_val && yield_val.finite? ? yield_val : nil
      }
    end
  end

  def load_dividend_events(stock, headers)
    primary_rows = fetch_bonus_history_rows(stock, headers)
    return primary_rows if primary_rows.any?

    fetch_report_rows(stock, headers)
  end

  def persist_dividend_events(stock, events, latest_price)
    records_created = 0
    fallback_price = latest_price.to_f

    merged_by_date = {}
    events.each do |attrs|
      date = attrs[:report_date]
      next unless date

      existing = merged_by_date[date]
      if existing
        existing[:cash_dividend] = existing[:cash_dividend].to_f + attrs[:cash_dividend].to_f
        existing[:bonus_issue] = existing[:bonus_issue].to_f + attrs[:bonus_issue].to_f
        existing[:rights_issue] = existing[:rights_issue].to_f + attrs[:rights_issue].to_f
        existing[:notice_date] = [existing[:notice_date], attrs[:notice_date]].compact.min
        existing[:ex_dividend_date] ||= attrs[:ex_dividend_date]
        existing[:fiscal_year] ||= attrs[:fiscal_year]

        descs = [existing[:plan_description].to_s.strip, attrs[:plan_description].to_s.strip].reject(&:empty?).uniq
        existing[:plan_description] = descs.join('；') if descs.any?

        existing_yield = existing[:dividend_yield]
        incoming_yield = attrs[:dividend_yield]
        if existing_yield.nil? || existing_yield.to_f <= 0
          existing[:dividend_yield] = incoming_yield
        end
      else
        merged_by_date[date] = attrs.dup
      end
    end

    Dividend.transaction do
      Dividend.where(stock_id: stock.id).delete_all

      merged_by_date.keys.sort.each do |date|
        attrs = merged_by_date[date]
        div = Dividend.new(stock_id: stock.id)
        div.report_date = attrs[:report_date]
        div.notice_date = attrs[:notice_date]
        div.ex_dividend_date = attrs[:ex_dividend_date] if div.has_attribute?(:ex_dividend_date)
        div.fiscal_year = attrs[:fiscal_year] if div.has_attribute?(:fiscal_year)
        div.plan_description = attrs[:plan_description]
        div.cash_dividend = attrs[:cash_dividend]
        div.bonus_issue = attrs[:bonus_issue]
        div.rights_issue = attrs[:rights_issue]

        yield_val = attrs[:dividend_yield]
        if (yield_val.nil? || yield_val.to_f <= 0) && fallback_price.positive? && attrs[:cash_dividend].to_f > 0
          yield_val = (attrs[:cash_dividend].to_f / fallback_price) * 100.0
        end
        div.dividend_yield = yield_val

        div.save!
        records_created += 1
      end
    end

    records_created
  end

  def fetch_and_save_dividends(stock)
    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'application/json, text/plain, */*',
      'X-Requested-With' => 'XMLHttpRequest'
    }
    latest_price = stock.current_price || stock.price_histories.order(date: :desc).limit(1).pluck(:close).first
    results = load_dividend_events(stock, headers)
    
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

    records_created = persist_dividend_events(stock, results, latest_price)
    normalized_rows =
      DividendMetrics.normalized_rows(
        stock.dividends.order(report_date: :desc).to_a,
        future_dividends: stock.future_dividends.where('ex_dividend_date <= ?', Date.today).to_a
      )

    if normalized_rows.any?
      if stock.has_attribute?(:consecutive_dividend_years)
        stock.consecutive_dividend_years = DividendMetrics.consecutive_years(normalized_rows)
      end

      dps_year, dps_val = DividendMetrics.latest_cash_for_year(normalized_rows)

      stock.dividend_cash_per_share_year = dps_year if stock.has_attribute?(:dividend_cash_per_share_year)
      stock.dividend_cash_per_share_latest_year = dps_val if stock.has_attribute?(:dividend_cash_per_share_latest_year)

      ttm_sum = DividendMetrics.ttm_cash(normalized_rows)

      if latest_price && latest_price.to_f > 0 && ttm_sum.to_f > 0
        stock.dividend_yield = (ttm_sum.to_f / latest_price.to_f) * 100.0
      else
        stock.dividend_yield = nil
      end

      if stock.has_attribute?(:expected_dividend_yield)
        if latest_price && latest_price.to_f > 0 && ttm_sum.to_f > 0
          stock.expected_dividend_yield = (ttm_sum.to_f / latest_price.to_f) * 100.0
        elsif latest_price && latest_price.to_f > 0 && dps_val.to_f > 0
          stock.expected_dividend_yield = (dps_val.to_f / latest_price.to_f) * 100.0
        else
          stock.expected_dividend_yield = 0.0
        end
      end

      if stock.has_attribute?(:avg_dividend_yield_3y)
        years = DividendMetrics.trailing_years(normalized_rows, count: 3)
        if latest_price && latest_price.to_f > 0
          per_year = DividendMetrics.annual_cash(normalized_rows)
          dps_values = years.map { |y| per_year[y].to_f }
          dps_values = [] if dps_values.size != 3 || dps_values.any? { |dps| dps <= 0 }

          if dps_values.size == 3
            yields = dps_values.map { |dps| (dps / latest_price.to_f) * 100.0 }
            stock.avg_dividend_yield_3y = yields.sum / 3.0
            stock.min_dividend_yield_3y = yields.min if stock.has_attribute?(:min_dividend_yield_3y)
          else
            stock.avg_dividend_yield_3y = nil
            stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
          end
        else
          stock.avg_dividend_yield_3y = nil
          stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
        end
      end
    else
      stock.dividend_yield = nil
      stock.dividend_cash_per_share_year = nil if stock.has_attribute?(:dividend_cash_per_share_year)
      stock.dividend_cash_per_share_latest_year = nil if stock.has_attribute?(:dividend_cash_per_share_latest_year)
      stock.avg_dividend_yield_3y = nil if stock.has_attribute?(:avg_dividend_yield_3y)
      stock.min_dividend_yield_3y = nil if stock.has_attribute?(:min_dividend_yield_3y)
      stock.consecutive_dividend_years = nil if stock.has_attribute?(:consecutive_dividend_years)
      stock.expected_dividend_yield = 0.0 if stock.has_attribute?(:expected_dividend_yield)
    end
    stock.save! if stock.changed?

    puts "Saved #{records_created} dividend records for #{stock.name}."
  end
end
