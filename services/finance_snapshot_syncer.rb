require 'faraday'
require 'faraday/retry'
require 'json'
require 'date'

class FinanceSnapshotSyncer
  def initialize(scope: Stock.all, sleep_range: (0.04..0.10))
    @scope = scope
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
    resp = conn.get('https://datacenter-web.eastmoney.com/api/data/v1/get', {
      reportName: 'RPT_F10_FINANCE_MAINFINADATA',
      columns: 'ALL',
      pageNumber: 1,
      pageSize: 1,
      sortColumns: 'REPORT_DATE',
      sortTypes: -1,
      source: 'WEB',
      client: 'WEB',
      filter: "(SECURITY_CODE=\"#{code}\")"
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

    row = (parsed.dig('result', 'data') || []).first
    return unless row.is_a?(Hash) && !row.empty?

    report_date = parse_date(row['REPORT_DATE'])
    revenue_yoy = parse_decimal(row['DJD_TOI_YOY']) || parse_decimal(row['OI_YOYRATIO_PK'])
    net_profit_yoy = parse_decimal(row['DJD_DPNP_YOY'])
    net_profit_yoy_deducted = parse_decimal(row['DJD_DEDUCTDPNP_YOY'])

    total_assets = parse_bigint(row['TOTAL_ASSETS_PK'])
    total_liabilities = parse_bigint(row['LIABILITY'])
    asset_liability_ratio =
      if total_assets && total_assets > 0 && total_liabilities && total_liabilities >= 0
        (total_liabilities.to_f / total_assets.to_f) * 100.0
      end

    interest_debt_ratio = parse_decimal(row['INTEREST_DEBT_RATIO'])
    fcff_back = parse_decimal(row['FCFF_BACK'])
    market_cap = stock.market_cap.to_f
    fcf_yield =
      if fcff_back && market_cap.finite? && market_cap > 0
        (fcff_back.to_f / market_cap) * 100.0
      end
    fcf_ev =
      if fcff_back && market_cap.finite? && market_cap > 0 && total_liabilities && total_liabilities > 0 && interest_debt_ratio
        interest_debt_amount = (interest_debt_ratio.to_f / 100.0) * total_liabilities.to_f
        ev = market_cap + interest_debt_amount
        ev > 0 ? (fcff_back.to_f / ev) * 100.0 : nil
      end

    growth = net_profit_yoy_deducted || net_profit_yoy
    peg = compute_peg(stock.pe_ttm, growth)
    peg_level = peg_level_for(peg, growth)

    stock.update!(
      finance_report_date: report_date,
      revenue_yoy: revenue_yoy,
      net_profit_yoy: net_profit_yoy,
      net_profit_yoy_deducted: net_profit_yoy_deducted,
      total_assets: total_assets,
      total_liabilities: total_liabilities,
      asset_liability_ratio: asset_liability_ratio,
      interest_debt_ratio: interest_debt_ratio,
      fcff_back: fcff_back,
      fcf_yield: fcf_yield,
      fcf_ev: fcf_ev,
      peg: peg,
      peg_level: peg_level
    )
  rescue Faraday::Error, StandardError => e
    puts "finance_sync_error code=#{stock.code} error=#{e.class}: #{e.message}"
    nil
  end

  def compute_peg(pe_ttm, growth_pct)
    pe = pe_ttm.to_f
    g = growth_pct.to_f
    return nil unless pe.finite? && pe > 0
    return nil unless g.finite? && g > 0
    pe / g
  end

  def peg_level_for(peg, growth_pct)
    g = growth_pct.to_f
    return 5 if g.finite? && g < 0

    p = peg.to_f
    return nil unless p.finite? && p > 0
    return 1 if p < 0.5
    return 2 if p < 1.0
    return 3 if p <= 1.5
    4
  end

  def parse_date(v)
    return nil if v.nil?
    s = v.to_s.strip
    return nil if s.empty? || s == '-' || s == '0'
    Date.parse(s) rescue nil
  end

  def parse_decimal(v)
    return nil if v.nil?
    s = v.to_s.strip
    return nil if s.empty? || s == '-' || s == '0'
    n = Float(s) rescue nil
    return nil unless n && n.finite?
    n
  end

  def parse_bigint(v)
    return nil if v.nil?
    n = v.is_a?(Numeric) ? v : (Integer(v.to_s) rescue nil)
    n && n.to_i
  end
end
