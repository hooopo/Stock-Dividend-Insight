require 'faraday'
require 'faraday/retry'
require 'json'
require 'date'

class RoeHistorySyncer
  def initialize(scope: Stock.all, years: 12, sleep_range: (0.04..0.10))
    @scope = scope
    @years = years.to_i
    @years = 12 if @years <= 0
    @sleep_range = sleep_range
  end

  def sync
    conn = Faraday.new do |f|
      f.request :url_encoded
      f.request :retry, max: 3, interval: 0.05,
                       interval_randomness: 0.5, backoff_factor: 2,
                       exceptions: [Faraday::Error, JSON::ParserError]
      f.adapter Faraday.default_adapter
    end

    @scope.order(:id).find_each do |stock|
      sync_one(conn, stock)
      sleep(rand(@sleep_range)) if @sleep_range
    end
  end

  private

  def sync_one(conn, stock)
    code = stock.code.to_s.rjust(6, '0')
    from_date = Date.today << (@years * 12)
    from_str = from_date.strftime('%Y-%m-%d')

    page = 1
    page_size = 50
    total_pages = 1
    latest_row = nil

    while page <= total_pages
      resp = conn.get('https://datacenter-web.eastmoney.com/api/data/v1/get', {
        reportName: 'RPT_F10_FINANCE_MAINFINADATA',
        columns: 'SECURITY_CODE,REPORT_DATE,REPORT_TYPE,REPORT_YEAR,ROEJQ,ROEKCJQ,NOTICE_DATE,UPDATE_DATE',
        pageNumber: page,
        pageSize: page_size,
        sortColumns: 'REPORT_DATE',
        sortTypes: -1,
        source: 'WEB',
        client: 'WEB',
        filter: "(SECURITY_CODE=\"#{code}\")(REPORT_DATE>='#{from_str}')"
      }, {
        'User-Agent' => 'Mozilla/5.0',
        'Referer' => 'https://data.eastmoney.com/',
        'Connection' => 'close'
      }) do |req|
        req.options.timeout = 15
        req.options.open_timeout = 8
      end
      return unless resp.success?

      parsed = JSON.parse(resp.body) rescue nil
      return unless parsed && parsed['code'].to_i == 0

      result = parsed['result'] || {}
      total_pages = result['pages'].to_i
      total_pages = 1 if total_pages <= 0
      rows = result['data']
      break unless rows.is_a?(Array) && !rows.empty?

      latest_row ||= rows.first

      rows.each do |row|
        report_date = parse_date(row['REPORT_DATE'])
        next unless report_date

        rh = stock.roe_histories.find_or_initialize_by(report_date: report_date)
        rh.report_type = row['REPORT_TYPE']
        rh.report_year = row['REPORT_YEAR']
        rh.roe_jq = parse_decimal(row['ROEJQ'])
        rh.roe_kc_jq = parse_decimal(row['ROEKCJQ'])
        rh.notice_date = parse_date(row['NOTICE_DATE'])
        rh.update_date = parse_date(row['UPDATE_DATE'])
        rh.save! if rh.changed?
      end

      page += 1
    end

    return unless latest_row

    roe_jq = parse_decimal(latest_row['ROEJQ'])
    roe_kc_jq = parse_decimal(latest_row['ROEKCJQ'])

    flags = compute_roe_5y_flags(stock)
    stock.update!(
      roe_jq: roe_jq,
      roe_kc_jq: roe_kc_jq,
      roe_report_date: parse_date(latest_row['REPORT_DATE']),
      roe_report_type: latest_row['REPORT_TYPE'].to_s,
      roe_level: roe_level_for(roe_jq),
      roe_5y_avg_ge_12: flags[:roe_5y_avg_ge_12],
      roe_5y_min_ge_8: flags[:roe_5y_min_ge_8],
      roe_5y_std: flags[:roe_5y_std],
      roe_trend_score: flags[:roe_trend_score]
    )
  rescue Faraday::Error, StandardError => e
    puts "roe_sync_error code=#{stock.code} error=#{e.class}: #{e.message}"
    nil
  end

  def compute_roe_5y_flags(stock)
    rows =
      stock
        .roe_histories
        .where(report_type: '年报')
        .where.not(roe_jq: nil)
        .order(report_date: :desc)
        .limit(5)
        .pluck(:roe_jq)
        .map(&:to_f)

    return { roe_5y_avg_ge_12: false, roe_5y_min_ge_8: false, roe_5y_std: nil, roe_trend_score: nil } if rows.size < 5

    avg = rows.sum / rows.size.to_f
    min = rows.min
    var = rows.map { |x| (x - avg) ** 2 }.sum / rows.size.to_f
    std = Math.sqrt(var)

    slope = theil_sen_slope(rows)
    spearman = spearman_corr(rows)
    slope_score = (Math.tanh(slope / 3.0) + 1.0) / 2.0
    spearman_score = (spearman + 1.0) / 2.0
    std_score = 1.0 / (1.0 + (std / 5.0))
    trend_score = 100.0 * (0.5 * slope_score + 0.3 * spearman_score + 0.2 * std_score)

    {
      roe_5y_avg_ge_12: avg >= 12.0,
      roe_5y_min_ge_8: min >= 8.0,
      roe_5y_std: std,
      roe_trend_score: trend_score
    }
  end

  def roe_level_for(roe_jq)
    return nil if roe_jq.nil?
    v = roe_jq.to_f
    return 3 if v > 20.0
    return 2 if v > 15.0
    1
  end

  def parse_decimal(value)
    return nil if value.nil?
    s = value.to_s.strip
    return nil if s.empty? || s == '-'
    Float(s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_date(value)
    s = value.to_s.strip
    return nil if s.empty?
    Date.parse(s)
  rescue ArgumentError
    nil
  end

  def theil_sen_slope(values)
    ys = Array(values).map(&:to_f)
    n = ys.size
    return 0.0 if n < 2

    slopes = []
    (0...n).each do |i|
      (i + 1...n).each do |j|
        dx = (j - i).to_f
        next if dx.abs < 1e-9
        slopes << ((ys[j] - ys[i]) / dx)
      end
    end
    median(slopes)
  end

  def spearman_corr(values)
    ys = Array(values).map(&:to_f)
    n = ys.size
    return 0.0 if n < 2

    xr = (1..n).map(&:to_f)
    yr = rank_with_ties(ys)
    pearson_corr(xr, yr)
  end

  def rank_with_ties(values)
    arr = values.map(&:to_f)
    indexed = arr.each_with_index.map { |v, i| [v, i] }.sort_by { |v, _| v }
    ranks = Array.new(arr.size)

    i = 0
    while i < indexed.size
      j = i
      j += 1 while j < indexed.size && (indexed[j][0] - indexed[i][0]).abs < 1e-12
      avg_rank = ((i + 1) + j).to_f / 2.0
      (i...j).each do |k|
        ranks[indexed[k][1]] = avg_rank
      end
      i = j
    end

    ranks
  end

  def pearson_corr(x, y)
    xs = Array(x).map(&:to_f)
    ys = Array(y).map(&:to_f)
    n = [xs.size, ys.size].min
    return 0.0 if n < 2

    mx = xs.sum / n.to_f
    my = ys.sum / n.to_f
    cov = 0.0
    vx = 0.0
    vy = 0.0
    n.times do |i|
      dx = xs[i] - mx
      dy = ys[i] - my
      cov += dx * dy
      vx += dx * dx
      vy += dy * dy
    end
    return 0.0 if vx <= 0.0 || vy <= 0.0
    cov / Math.sqrt(vx * vy)
  end

  def median(values)
    arr = Array(values).map(&:to_f).sort
    return 0.0 if arr.empty?
    mid = arr.size / 2
    if arr.size.odd?
      arr[mid]
    else
      (arr[mid - 1] + arr[mid]) / 2.0
    end
  end
end
