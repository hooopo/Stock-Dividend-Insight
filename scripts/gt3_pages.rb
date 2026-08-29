require 'yaml'
require 'date'
require 'time'
require 'fileutils'
require 'digest'
require 'json'

ROOT_DIR = File.expand_path('..', __dir__)
IN_YML = File.join(ROOT_DIR, 'stocks-dividend-gt3.yml')
OUT_DIR = File.join(ROOT_DIR, 'docs', 'gt3')
OUT_HTML = File.join(OUT_DIR, 'index.html')
OUT_YML = File.join(OUT_DIR, 'data.yml')

require_relative '../models'

FileUtils.mkdir_p(OUT_DIR)

def format_num(v, precision = 2)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f", x)
end

def format_pct(v, precision = 2)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f%%", x)
end

def format_ratio_pct(v, precision = 0)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f%%", x * 100.0)
end

def format_yi(v, precision = 1)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f亿", x / 100_000_000.0)
end

def format_wanshou(v, precision = 2)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f万手", x / 10_000.0)
end

def format_yigu(v, precision = 2)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  format("%.#{precision}f亿股", x / 100_000_000.0)
end

def peg_level_label(level)
  case level.to_i
  when 1 then '极低估成长'
  when 2 then '优质成长'
  when 3 then '合理'
  when 4 then '偏贵'
  when 5 then '负增长'
  else
    ''
  end
end

CORE_CATEGORY_TOKENS = %w[
  银行 国有大行 城商行龙头 城商行
  电力 水电 火电龙头 火电 地方能源
  公用事业 燃气 水务
  交通 高速 铁路 港口 高速铁路
  通信 三大运营商 运营商
].freeze

WHITELIST_RAW = <<~EOF
银行|六大行|工商银行|601398|4.5|5.2|6.0
银行|六大行|建设银行|601939|4.5|5.2|6.0
银行|六大行|农业银行|601288|4.5|5.2|6.0
银行|六大行|中国银行|601988|4.5|5.2|6.0
银行|六大行|交通银行|601328|4.5|5.2|6.0
银行|六大行|邮储银行|601658|4.5|5.2|6.0
银行|股份行|招商银行|600036|4.8|5.5|6.2
银行|股份行|兴业银行|601166|5.0|6.0|7.0
银行|股份行|中信银行|601998|5.0|6.0|7.0
银行|股份行|光大银行|601818|5.0|6.0|7.0
银行|股份行|华夏银行|600015|5.0|6.0|7.0
银行|股份行|浦发银行|600000|5.0|6.0|7.0
银行|股份行|平安银行|000001|5.0|6.0|7.0
银行|城商行|北京银行|601169|5.0|6.0|7.0
银行|城商行|上海银行|601229|5.0|6.0|7.0
银行|城商行|江苏银行|600919|4.5|5.2|6.0
银行|城商行|南京银行|601009|4.5|5.2|6.0
银行|城商行|成都银行|601838|4.5|5.2|6.0
银行|城商行|杭州银行|600926|4.5|5.2|6.0
银行|农商行|沪农商行|601825|4.5|5.2|6.0
银行|农商行|苏州银行|002966|4.5|5.2|6.0
银行|农商行|常熟银行|601128|4.5|5.2|6.0
银行|农商行|齐鲁银行|601665|4.5|5.2|6.0
银行|农商行|渝农商行|601077|5.0|6.0|7.0
银行|农商行|长沙银行|601577|4.5|5.2|6.0
银行|城商行|贵阳银行|601997|5.0|6.0|7.0
银行|股份行|民生银行|600016|5.0|6.0|7.0
银行|股份行|浙商银行|601916|5.0|6.0|7.0
电力|水电|长江电力|600900|3.3|3.8|4.5
电力|水电|华能水电|600025|3.3|3.8|4.5
电力|水电|川投能源|600674|3.0|3.5|4.2
电力|水电|国投电力|600886|3.3|3.9|4.5
电力|水电|桂冠电力|600236|3.8|4.5|5.3
电力|核电|中国核电|601985|3.5|4.2|5.0
电力|核电|中国广核|003816|3.5|4.2|5.0
电力|综合能源|浙能电力|600023|5.0|5.8|6.8
电力|综合能源|申能股份|600642|4.5|5.2|6.0
电力|综合能源|福能股份|600483|3.8|4.5|5.3
电力|综合能源|广州发展|600098|4.5|5.3|6.2
电力|综合能源|新奥股份|600803|4.5|5.5|6.5
电力|火电|华能国际|600011|5.5|6.5|7.5
电力|火电|华电国际|600027|5.0|6.0|7.0
电力|火电|国电电力|600795|4.8|5.7|6.7
电力|火电|内蒙华电|600863|4.8|5.7|6.7
公用事业|高速|宁沪高速|600377|4.0|4.7|5.5
公用事业|高速|山东高速|600350|4.0|4.8|5.6
公用事业|高速|粤高速A|000429|4.2|5.0|5.8
公用事业|高速|招商公路|001965|4.2|5.0|5.8
公用事业|高速|皖通高速|600012|3.8|4.5|5.3
公用事业|港口|唐山港|601000|4.5|5.3|6.2
公用事业|港口|青岛港|601298|4.5|5.3|6.2
公用事业|港口|秦港股份|601326|4.5|5.3|6.2
公用事业|港口|上港集团|600018|3.5|4.1|4.8
公用事业|港口|宁波港|601018|3.3|3.9|4.6
公用事业|港口|盐田港|000088|4.0|4.7|5.5
公用事业|港口|招商港口|001872|3.2|3.8|4.5
公用事业|铁路|大秦铁路|601006|5.0|5.8|6.8
公用事业|通信|中国移动|600941|4.5|5.2|6.0
公用事业|通信|中国电信|601728|4.3|5.0|5.8
公用事业|通信|中国联通|600050|4.0|4.7|5.5
公用事业|环保|首创环保|600008|4.5|5.2|6.0
公用事业|环保|伟明环保|603568|3.5|4.2|5.0
公用事业|环保|瀚蓝环境|600323|4.0|4.8|5.6
公用事业|环保|洪城环境|600461|4.2|5.0|5.8
公用事业|燃气|新奥股份|600803|4.5|5.5|6.5
公用事业|燃气|蓝天燃气|605368|4.8|5.6|6.5
公用事业|燃气|深圳燃气|601139|4.3|5.0|5.8
周期|综合物流|中国外运|601598|5.0|5.8|6.8
周期|内贸航运|中谷物流|603565|7.0|8.0|9.5
EOF

def build_whitelist_map
  map = {}
  big_order = []
  sub_by_big = Hash.new { |h, k| h[k] = [] }
  seen = {}
  WHITELIST_RAW.split(/\n/).map(&:strip).reject(&:empty?).each do |line|
    big, sub, name, code, first, add, heavy = line.split('|').map(&:strip)
    code = code.rjust(6, '0')
    next unless code.match?(/^\d{6}$/)
    big_order << big unless seen.key?("big:#{big}")
    seen["big:#{big}"] = true
    unless seen.key?("sub:#{big}:#{sub}")
      sub_by_big[big] << sub
      seen["sub:#{big}:#{sub}"] = true
    end
    map[code] ||= {
      code: code,
      name: name,
      big_categories: [],
      sub_categories: [],
      first_yield: first.to_f,
      add_yield: add.to_f,
      heavy_yield: heavy.to_f
    }
    map[code][:big_categories] = (map[code][:big_categories] + [big]).uniq
    map[code][:sub_categories] = (map[code][:sub_categories] + [sub]).uniq
  end
  { map: map, big_order: big_order, sub_by_big: sub_by_big }
end

WHITELIST_BUILD = build_whitelist_map
WHITELIST_BY_CODE = WHITELIST_BUILD[:map]
WHITELIST_BIG_ORDER = WHITELIST_BUILD[:big_order]
WHITELIST_SUB_BY_BIG = WHITELIST_BUILD[:sub_by_big]

def whitelist_entry_for(code)
  return nil unless code
  WHITELIST_BY_CODE[code.to_s.strip.rjust(6, '0')]
end

def norm_category(s)
  s.to_s.strip.gsub(/\s+/, '').gsub(/[\/｜|、，,]/, '')
end

def core_hits_for(categories)
  cats = Array(categories).map(&:to_s)
  norms = cats.map { |c| norm_category(c) }
  hits = []
  norms.each_with_index do |c, idx|
    next if c.empty?
    CORE_CATEGORY_TOKENS.each do |t|
      next unless (c == t) || c.include?(t)
      hits << cats[idx]
      break
    end
  end
  hits.uniq
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

raise "missing #{IN_YML}" unless File.exist?(IN_YML)
data = YAML.load_file(IN_YML)
list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])
yml_rows =
  list.filter_map do |row|
    code = row['code'].to_s.strip.rjust(6, '0')
    next unless code.match?(/^\d{6}$/)
    name = row['name'].to_s.strip
    next if name.empty?
    { code: code, name: name, categories: Array(row['categories']).map(&:to_s) }
  end

codes = yml_rows.map { |x| x[:code] }.uniq

stock_cols = Stock.column_names.to_h { |c| [c, true] }
has_consecutive_dividend_years = stock_cols['consecutive_dividend_years']
has_min_dividend_yield_3y = stock_cols['min_dividend_yield_3y']

stock_pluck_keys = [:id, :code, :name]
[
  :avg_dividend_yield_3y,
  :min_dividend_yield_3y,
  :dividend_yield,
  :consecutive_dividend_years,
  :dividend_cash_per_share_latest_year,
  :current_price,
  :turnover_rate,
  :market_cap,
  :volume,
  :avg_price,
  :dividend_payout_ratio,
  :pos_30d,
  :pe_ttm,
  :pe_percentile,
  :valuation_label,
  :peg,
  :peg_level,
  :net_profit_yoy,
  :finance_report_date,
  :pb,
  :pb_percentile,
  :drop_30d,
  :asset_liability_ratio,
  :interest_debt_ratio,
  :fcf_yield,
  :fcf_ev,
  :fcff_back,
  :roe_jq,
  :roe_5y_avg_ge_12,
  :roe_5y_min_ge_8,
  :total_shares
].each do |k|
  stock_pluck_keys << k if stock_cols[k.to_s]
end

stocks =
  Stock
    .where(asset_type: 'stock', code: codes)
    .pluck(*stock_pluck_keys)
    .map do |vals|
      v = stock_pluck_keys.zip(vals).to_h
      {
        id: v[:id],
        code: v[:code].to_s.rjust(6, '0'),
        name: v[:name].to_s,
        avg_dividend_yield_3y: v[:avg_dividend_yield_3y]&.to_f,
        min_dividend_yield_3y: has_min_dividend_yield_3y ? v[:min_dividend_yield_3y]&.to_f : nil,
        dividend_yield: v[:dividend_yield]&.to_f,
        consecutive_dividend_years: has_consecutive_dividend_years ? v[:consecutive_dividend_years]&.to_i : nil,
        dividend_cash_per_share_latest_year: v[:dividend_cash_per_share_latest_year]&.to_f,
        current_price: v[:current_price]&.to_f,
        turnover_rate: v[:turnover_rate]&.to_f,
        market_cap: v[:market_cap]&.to_f,
        volume: v[:volume]&.to_f,
        avg_price: v[:avg_price]&.to_f,
        dividend_payout_ratio: v[:dividend_payout_ratio]&.to_f,
        pos_30d: v[:pos_30d]&.to_f,
        pe_ttm: v[:pe_ttm]&.to_f,
        pe_percentile: v[:pe_percentile]&.to_f,
        valuation_label: v[:valuation_label].to_s,
        peg: v[:peg]&.to_f,
        peg_level: v[:peg_level]&.to_i,
        net_profit_yoy: v[:net_profit_yoy]&.to_f,
        finance_report_date: v[:finance_report_date]&.to_s,
        pb: v[:pb]&.to_f,
        pb_percentile: v[:pb_percentile]&.to_f,
        drop_30d: v[:drop_30d]&.to_f,
        asset_liability_ratio: v[:asset_liability_ratio]&.to_f,
        interest_debt_ratio: v[:interest_debt_ratio]&.to_f,
        fcf_yield: v[:fcf_yield]&.to_f,
        fcf_ev: v[:fcf_ev]&.to_f,
        fcff_back: v[:fcff_back]&.to_f,
        roe_jq: v[:roe_jq]&.to_f,
        roe_5y_avg_ge_12: v[:roe_5y_avg_ge_12] == true,
        roe_5y_min_ge_8: v[:roe_5y_min_ge_8] == true,
        total_shares: v[:total_shares]&.to_f
      }
    end

categories_by_stock_id = {}
begin
  conn = ActiveRecord::Base.connection
  if conn.data_source_exists?('categorizations') && conn.data_source_exists?('categories')
    stock_ids_for_cats = stocks.map { |x| x[:id] }.compact.uniq
    if stock_ids_for_cats.any?
      pairs = Categorization.joins(:category).where(stock_id: stock_ids_for_cats).pluck(:stock_id, 'categories.name')
      categories_by_stock_id =
        pairs
          .group_by { |sid, _| sid }
          .transform_values { |xs| xs.map { |_, n| n.to_s.strip }.reject(&:empty?).uniq }
    end
  end
rescue StandardError
  categories_by_stock_id = {}
end

by_code = stocks.index_by { |x| x[:code] }

rows_out =
  yml_rows
    .filter_map do |row|
      m = by_code[row[:code]]
      next unless m

      cats = (Array(row[:categories]) + Array(categories_by_stock_id[m[:id]])).map(&:to_s).map(&:strip).reject(&:empty?).uniq
      core_hits = core_hits_for(cats)

      wl = whitelist_entry_for(row[:code])
      wl_cats_set = {}
      if wl
        Array(wl[:big_categories]).each { |c| wl_cats_set[c.to_s] = true }
        Array(wl[:sub_categories]).each { |c| wl_cats_set[c.to_s] = true }
      end
      wl_big = wl ? Array(wl[:big_categories]).first : nil
      wl_sub = wl ? Array(wl[:sub_categories]).first : nil
      wl_categories = wl ? (Array(wl[:big_categories]) + Array(wl[:sub_categories])).map(&:to_s).uniq : []

      price = m[:current_price]
      min3y = m[:min_dividend_yield_3y]

      if wl
        first_y = wl[:first_yield].to_f
        add_y = wl[:add_yield].to_f
        heavy_y = wl[:heavy_yield].to_f
        buy5 = (price && price > 0 && min3y && min3y > 0 && first_y > 0) ? (price * (min3y / first_y)) : nil
        buy6 = (price && price > 0 && min3y && min3y > 0 && add_y > 0) ? (price * (min3y / add_y)) : nil
        buy7 = (price && price > 0 && min3y && min3y > 0 && heavy_y > 0) ? (price * (min3y / heavy_y)) : nil
        first_yield_use = first_y
        add_yield_use = add_y
        heavy_yield_use = heavy_y
        buy_method = 'whitelist_min3y'
      else
        first_yield_use = nil
        add_yield_use = nil
        heavy_yield_use = nil
        buy5 = (price && price > 0 && min3y && min3y > 0) ? (price * (min3y / 5.0)) : nil
        buy6 = (price && price > 0 && min3y && min3y > 0) ? (price * (min3y / 6.0)) : nil
        buy7 = (price && price > 0 && min3y && min3y > 0) ? (price * (min3y / 7.0)) : nil
        buy_method = 'min3y'
      end

      drop5 = (buy5 && price && price > 0) ? ((1.0 - (buy5 / price)) * 100.0) : nil
      drop6 = (buy6 && price && price > 0) ? ((1.0 - (buy6 / price)) * 100.0) : nil
      drop7 = (buy7 && price && price > 0) ? ((1.0 - (buy7 / price)) * 100.0) : nil
      need_drop5 = drop5 ? [drop5.to_f, 0.0].max : nil

      row.merge(m).merge(
        categories: cats,
        is_core: core_hits.any?,
        core_categories: core_hits,
        is_whitelist: !!wl,
        whitelist_big_category: wl_big,
        whitelist_sub_category: wl_sub,
        whitelist_categories: wl_categories,
        first_yield: first_yield_use,
        add_yield: add_yield_use,
        heavy_yield: heavy_yield_use,
        buy_method: buy_method,
        buy_price_5: buy5,
        buy_price_6: buy6,
        buy_price_7: buy7,
        need_drop_to_5: need_drop5,
        drop_to_5: drop5,
        drop_to_6: drop6,
        drop_to_7: drop7
      )
    end

rows_out.sort_by! do |x|
  [
    x[:is_whitelist] ? 0 : 1,
    (x[:need_drop_to_5].nil? ? 1_000_000.0 : x[:need_drop_to_5].to_f),
    -(x[:avg_dividend_yield_3y] || 0).to_f,
    x[:code]
  ]
end

consecutive_map = {}
begin
  conn = ActiveRecord::Base.connection
  ids = rows_out.map { |x| x[:id] }.compact.uniq
  if ids.any? && conn.data_source_exists?('dividends')
    yearly_raw =
      Dividend
        .where(stock_id: ids)
        .pluck(:stock_id, :fiscal_year, :ex_dividend_date, :report_date, :cash_dividend, :plan_description)
    future_raw =
      if conn.data_source_exists?('future_dividends')
        FutureDividend
          .where(stock_id: ids)
          .where('ex_dividend_date <= ?', Date.today)
          .pluck(:stock_id, :ex_dividend_date, :cash_dividend_per_share, :plan_description)
      else
        []
      end

    per_year_by_sid = Hash.new { |h, k| h[k] = Hash.new(0.0) }
    seen = {}
    yearly_raw.each do |sid, fiscal_year, ex_dividend_date, report_date, cash, plan|
      year = fiscal_year.to_i
      year = ex_dividend_date&.year if year <= 0
      year = report_date&.year if year <= 0
      next unless sid && year && year > 0
      seen[[sid, ex_dividend_date&.to_s, format('%.6f', cash.to_f), plan.to_s]] = true
      per_year_by_sid[sid][year] += cash.to_f
    end
    future_raw.each do |sid, ex_dividend_date, cash, _plan|
      year = ex_dividend_date&.year
      next unless sid && year && year > 0
      next if seen[[sid, ex_dividend_date&.to_s, format('%.6f', cash.to_f), _plan.to_s]]
      per_year_by_sid[sid][year] += cash.to_f
    end

    per_year_by_sid.each do |sid, per_year|
      consecutive_map[sid] = calc_consecutive_dividend_years(per_year)
    end
  end
rescue StandardError
  consecutive_map = {}
end

rows_out.each do |r|
  next unless r[:id]
  r[:consecutive_dividend_years] = consecutive_map[r[:id]] if consecutive_map.key?(r[:id])
end

roe_5y = {}
begin
  conn = ActiveRecord::Base.connection
  if conn.data_source_exists?('roe_histories')
    pairs =
      RoeHistory
        .where(stock_id: rows_out.map { |x| x[:id] }.uniq, report_type: '年报')
        .where.not(roe_jq: nil)
        .order(stock_id: :asc, report_date: :desc)
        .pluck(:stock_id, :roe_jq)
    grouped = Hash.new { |h, k| h[k] = [] }
    pairs.each do |sid, v|
      a = grouped[sid]
      next if a.size >= 5
      f = v.to_f
      next unless f.finite?
      a << f
    end
    roe_5y = grouped.transform_values do |arr|
      if arr.size >= 5
        { avg: arr.sum / arr.size.to_f, min: arr.min }
      else
        { avg: nil, min: nil }
      end
    end
  end
rescue StandardError
  roe_5y = {}
end

rows_out.each do |r|
  s = roe_5y[r[:id]]
  next unless s
  r[:roe_5y_avg] = s[:avg]
  r[:roe_5y_min] = s[:min]
end

stock_ids = rows_out.map { |x| x[:id] }.uniq

annual_dividends_by_stock_id = {}
begin
  conn = ActiveRecord::Base.connection
  if stock_ids.any? && conn.data_source_exists?('dividends')
    yearly_raw =
      Dividend
        .where(stock_id: stock_ids)
        .pluck(:stock_id, :report_date, :cash_dividend, :dividend_yield)

    grouped = Hash.new { |h, k| h[k] = Hash.new { |h2, y| h2[y] = { cash: 0.0, yield: 0.0 } } }
    yearly_raw.each do |sid, report_date, cash_dividend, dividend_yield|
      next unless sid && report_date
      year = report_date.year
      grouped[sid][year][:cash] += cash_dividend.to_f if cash_dividend
      grouped[sid][year][:yield] += dividend_yield.to_f if dividend_yield
    end

    grouped.each do |sid, per_year|
      years = per_year.keys.compact.sort
      next if years.empty?
      annual_dividends_by_stock_id[sid] =
        (years.min..years.max).map do |year|
          v = per_year[year] || { cash: 0.0, yield: 0.0 }
          {
            year: year,
            cash_dividend: v[:cash].round(4),
            dividend_yield: v[:yield].round(4)
          }
        end
    end
  end
rescue StandardError
  annual_dividends_by_stock_id = {}
end

rows_out.each do |r|
  r[:annual_dividends] = annual_dividends_by_stock_id[r[:id]] || []
end

start_date = Date.today
end_date = Date.today + 183
upcoming =
  FutureDividend
    .includes(:stock)
    .where(stock_id: stock_ids)
    .where(ex_dividend_date: start_date..end_date)
    .order(ex_dividend_date: :asc, security_code: :asc)
    .limit(1000)
    .map do |fd|
      {
        code: (fd.security_code.to_s.strip.empty? ? fd.stock&.code.to_s : fd.security_code.to_s).rjust(6, '0'),
        name: fd.security_name.to_s.strip.empty? ? fd.stock&.name.to_s : fd.security_name.to_s,
        ex_dividend_date: fd.ex_dividend_date&.to_s,
        equity_record_date: fd.equity_record_date&.to_s,
        notice_date: fd.notice_date&.to_s,
        cash_dividend_per_share: fd.cash_dividend_per_share&.to_f,
        dividend_yield_pct: fd.dividend_yield_pct&.to_f,
        progress: fd.progress.to_s,
        plan_description: fd.plan_description.to_s
      }
    end

generated_at_bj = Time.now.getlocal('+08:00').to_date.to_s

wl_big_count = WHITELIST_BIG_ORDER.size
wl_count = rows_out.count { |r| r[:is_whitelist] }

category_options_html_parts = []
category_options_html_parts << ['', '全部分类']
WHITELIST_BIG_ORDER.each do |big|
  category_options_html_parts << ["big:#{big}", "大分类：#{big}"]
  subs = WHITELIST_SUB_BY_BIG[big] || []
  subs.each do |sub|
    category_options_html_parts << ["sub:#{big}:#{sub}", "  #{big} / #{sub}"]
  end
end
category_options_html =
  category_options_html_parts
    .map { |v, label| "<option value=\"#{v}\">#{label}</option>" }
    .join("\n")

html = <<~HTML
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>GT3 红利列表</title>
  <style>
    body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,"PingFang SC","Hiragino Sans GB","Microsoft YaHei",sans-serif;margin:0;padding:24px;background:#f7f7fb;color:#111}
    h1{margin:0 0 8px 0;font-size:20px}
    .meta{color:#666;font-size:12px;margin-bottom:16px}
    .card{background:#fff;border:1px solid #eee;border-radius:10px;padding:16px;margin-bottom:16px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
    .table-wrap{overflow-x:auto;-webkit-overflow-scrolling:touch}
    table{border-collapse:collapse;width:100%;font-size:12px}
    th,td{border-bottom:1px solid #eee;padding:8px 10px;vertical-align:middle}
    th{position:sticky;top:0;background:#fff;cursor:pointer;user-select:none;white-space:nowrap}
    td{white-space:nowrap}
    .right{text-align:right}
    .search{width:280px;max-width:100%;padding:8px 10px;border:1px solid #ddd;border-radius:8px;font-size:12px}
    .row-hidden{display:none}
    .name-code{white-space:normal;line-height:1.25}
    .code{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;color:#888;font-size:11px;margin-top:2px}
    .check{display:inline-flex;align-items:center;gap:6px;border:1px solid #ddd;background:#fff;border-radius:999px;padding:8px 10px;font-size:12px;color:#111}
    .check input{width:14px;height:14px}
    .row-click{cursor:pointer}
    .detail{white-space:normal}
    .price-hit{font-weight:700;color:#c1121f}
    .detail-card{background:#fafafe;border:1px solid #eee;border-radius:10px;padding:12px}
    .detail-top{display:grid;grid-template-columns:minmax(0,1.5fr) minmax(280px,1fr);gap:12px;margin-bottom:12px}
    .chart-card,.metrics-card{background:#fff;border:1px solid #eee;border-radius:10px;padding:12px}
    .detail-title{font-size:13px;font-weight:700;color:#111;margin-bottom:4px}
    .detail-sub{font-size:11px;color:#666}
    .chart-legend{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin:8px 0 4px}
    .chart-legend-item{display:flex;align-items:center;gap:6px;font-size:11px;color:#475569}
    .chart-legend-bar{width:12px;height:12px;border-radius:4px;background:linear-gradient(180deg,#60a5fa 0%,#2563eb 100%)}
    .chart-legend-line{position:relative;width:16px;height:10px}
    .chart-legend-line::before{content:"";position:absolute;left:0;right:0;top:4px;border-top:2px solid #ef4444}
    .chart-legend-line::after{content:"";position:absolute;left:6px;top:1px;width:6px;height:6px;border-radius:999px;background:#ef4444}
    .div-chart-scroll{overflow:hidden;padding-bottom:4px}
    .div-chart{--plot-height:110px;display:grid;grid-template-columns:repeat(var(--chart-count, 1), minmax(0, 1fr));align-items:end;gap:var(--chart-gap, 4px);min-height:188px;min-width:0;padding-top:8px;width:100%;position:relative}
    .div-col{min-width:0;text-align:center;position:relative;z-index:1}
    .div-yield{font-size:10px;color:#475569;line-height:1.1;min-height:22px;margin-bottom:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .div-bar-wrap{height:var(--plot-height);display:flex;align-items:flex-end;justify-content:center}
    .div-bar{width:min(100%, var(--bar-width, 18px));min-height:2px;border-radius:8px 8px 0 0;background:linear-gradient(180deg,#60a5fa 0%,#2563eb 100%)}
    .div-year{font-size:10px;color:#111;margin-top:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .div-line-svg{position:absolute;left:0;top:36px;width:100%;height:var(--plot-height);pointer-events:none;overflow:visible;z-index:2}
    .div-line-path{fill:none;stroke:#ef4444;stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}
    .div-line-dot{fill:#ef4444;stroke:#fff;stroke-width:1.2}
    .chart-empty{font-size:12px;color:#666;padding:20px 0}
    .kv{display:flex;flex-wrap:wrap;gap:10px 10px}
    .kv-item{display:flex;align-items:center;gap:8px;background:#fff;border:1px solid #eee;border-radius:999px;padding:6px 10px;font-size:12px}
    .kv-item b{color:#555;font-weight:600}
    .kv-item span{color:#111}
    .kv-full{flex:1 1 100%;border-radius:10px}
    .only-mobile{display:none}
    .h-mobile{display:none}
    .ladder-lines{display:flex;flex-direction:column;gap:2px;align-items:flex-end}
    .ladder-lines span{white-space:nowrap}
    .yield-lines{display:flex;flex-direction:column;gap:2px;align-items:flex-end}
    .yield-lines span{white-space:nowrap}
    .payout-warn{display:inline-block;padding:1px 6px;border-radius:999px;background:#fff1f2;color:#be123c;font-size:10px;margin-left:6px}
    .sel{appearance:none;border:1px solid #ddd;background:#fff;border-radius:8px;padding:8px 10px;font-size:12px;color:#111;max-width:100%}
    @media (max-width: 640px){
      body{padding:12px}
      .card{padding:12px}
      th,td{padding:5px 6px}
      table{font-size:10.5px}
      h1{font-size:18px}
      .detail-card{padding:10px}
      .kv-item{font-size:11px;padding:6px 9px}
      .search{width:100%}
      .only-desktop{display:none}
      .only-mobile{display:table-cell}
      .h-desktop{display:none}
      .h-mobile{display:inline}
      th,td{letter-spacing:-0.1px}
      .code{font-size:10px}
      .detail-top{grid-template-columns:1fr}
      .chart-card,.metrics-card{padding:10px}
      .div-chart{gap:var(--chart-gap, 3px)}
      .div-bar{width:min(100%, var(--bar-width, 14px))}
    }
    @media (max-width: 430px){
      body{padding:10px;background:#f5f7fb}
      .card{padding:10px;border-radius:12px}
      h1{font-size:16px}
      .meta{font-size:11px;line-height:1.45}
      table{font-size:10px}
      th,td{padding:4px 5px}
      .search,.sel{width:100%;font-size:12px;padding:8px 9px}
      .check{padding:7px 9px;font-size:11px}
      .code,.payout-warn{font-size:9px}
      .ladder-lines,.yield-lines{gap:1px}
      .detail-card{padding:8px}
      .kv{gap:8px}
      .kv-item{font-size:10px;padding:5px 8px}
      .detail-top{gap:8px;margin-bottom:8px}
      .detail-title{font-size:12px}
      .detail-sub,.chart-empty,.div-yield,.div-year,.chart-legend-item{font-size:9px}
      .div-chart{gap:var(--chart-gap, 2px);min-height:168px}
      .div-chart{--plot-height:96px}
      .div-bar{width:min(100%, var(--bar-width, 12px))}
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>GT3 红利列表（默认白名单，勾选“显示全部”可查看全部 GT3 股票）</h1>
    <div class="meta">生成日期（北京时间）：#{generated_at_bj} · 总行数：#{rows_out.size} · 白名单：#{wl_count} · 大分类数：#{wl_big_count}</div>
    <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center">
      <input id="q" class="search" placeholder="搜索 名称/代码" />
      <select id="catSel" class="sel"><option value="">白名单分类</option>#{category_options_html}</select>
      <label class="check"><input id="wlOnly" type="checkbox" checked />仅白名单</label>
    </div>
  </div>

  <div class="card" id="captureMain">
    <div class="table-wrap" id="captureTable">
    <table id="t">
      <thead>
        <tr>
          <th data-k="namecode" data-t="str"><span class="h-desktop">名称/代码</span><span class="h-mobile">名称</span></th>
          <th class="right" data-k="price" data-t="num"><span class="h-desktop">最新价</span><span class="h-mobile">价格</span></th>
          <th class="right" data-k="yields" data-t="num"><span class="h-desktop">股息率(新/均/低)</span><span class="h-mobile">股息率</span></th>
          <th class="right" data-k="cdy" data-t="num"><span class="h-desktop">连续分红(年)</span><span class="h-mobile">连续分红</span></th>
          <th class="right" data-k="needDrop" data-t="num"><span class="h-desktop">需跌幅(首)</span><span class="h-mobile">需跌幅</span></th>
          <th class="right only-desktop" data-k="p5" data-t="num">首仓价(目标息率)</th>
          <th class="right only-desktop" data-k="p6" data-t="num">加仓价(目标息率)</th>
          <th class="right only-desktop" data-k="p7" data-t="num">重仓价(目标息率)</th>
          <th class="right only-mobile" data-k="p5" data-t="num"><span class="h-desktop">目标价</span><span class="h-mobile">首/加/重</span></th>
        </tr>
      </thead>
      <tbody>
HTML

rows_out.each do |r|
  key = Digest::MD5.hexdigest("#{r[:code]}|#{r[:name]}")
  namecode = "#{r[:name]} #{r[:code]}"
  cur_price = r[:current_price].to_f
  cur_price_ok = r[:current_price] && cur_price.finite?
  first_yield_tag = r[:first_yield] ? format_pct(r[:first_yield], 1) : '5%'
  add_yield_tag = r[:add_yield] ? format_pct(r[:add_yield], 1) : '6%'
  heavy_yield_tag = r[:heavy_yield] ? format_pct(r[:heavy_yield], 1) : '7%'
  p5_header = "首仓价(#{first_yield_tag})"
  p6_header = "加仓价(#{add_yield_tag})"
  p7_header = "重仓价(#{heavy_yield_tag})"
  payout_warn = (r[:dividend_payout_ratio].to_f > 80.0) ? '<span class="payout-warn">分红率过高</span>' : ''
  wl_big = r[:whitelist_big_category].to_s
  wl_sub = r[:whitelist_sub_category].to_s

  html << "<tr class=\"row-click main\" data-id=\"#{key}\" data-core=\"#{r[:is_core] ? 1 : 0}\" data-wl=\"#{r[:is_whitelist] ? 1 : 0}\" data-wlbig=\"#{wl_big}\" data-wlsub=\"#{wl_sub}\" data-avg3y=\"#{r[:avg_dividend_yield_3y]}\" data-min3y=\"#{r[:min_dividend_yield_3y]}\" data-firstyield=\"#{r[:first_yield]}\" data-addyield=\"#{r[:add_yield]}\" data-heavyyield=\"#{r[:heavy_yield]}\">"
  html << "<td class=\"name-code\" data-label=\"名称/代码\" data-v=\"#{namecode}\">#{r[:name]}#{payout_warn}<div class=\"code\">#{r[:code]}#{wl_big != '' ? ' · ' + [wl_big, wl_sub].reject(&:empty?).join(' / ') : ''}</div></td>"
  html << "<td class=\"right\" data-label=\"最新价\" data-v=\"#{r[:current_price]}\">#{format_num(r[:current_price], 2)}</td>"
  html << "<td class=\"right\" data-label=\"股息率\" data-v=\"#{r[:dividend_yield]}\"><div class=\"yield-lines\"><span><span style=\"color:#666\">新</span> #{format_pct(r[:dividend_yield], 2)}</span><span><span style=\"color:#666\">均</span> #{format_pct(r[:avg_dividend_yield_3y], 2)}</span><span><span style=\"color:#666\">低</span> #{format_pct(r[:min_dividend_yield_3y], 2)}</span></div></td>"
  html << "<td class=\"right\" data-label=\"连续分红(年)\" data-v=\"#{r[:consecutive_dividend_years]}\">#{r[:consecutive_dividend_years].to_i if r[:consecutive_dividend_years]}</td>"
  html << "<td class=\"right\" data-label=\"需跌幅\" data-v=\"#{r[:need_drop_to_5]}\">#{format_pct(r[:need_drop_to_5], 2)}</td>"
  hit5 = cur_price_ok && r[:buy_price_5] && cur_price <= r[:buy_price_5].to_f
  hit6 = cur_price_ok && r[:buy_price_6] && cur_price <= r[:buy_price_6].to_f
  hit7 = cur_price_ok && r[:buy_price_7] && cur_price <= r[:buy_price_7].to_f
  html << "<td class=\"right only-desktop#{hit5 ? ' price-hit' : ''}\" data-label=\"#{p5_header}\" data-v=\"#{r[:buy_price_5]}\" title=\"目标息率 #{first_yield_tag}（#{r[:buy_method]}）\">#{format_num(r[:buy_price_5], 2)}<div class=\"code\">#{first_yield_tag}</div></td>"
  html << "<td class=\"right only-desktop#{hit6 ? ' price-hit' : ''}\" data-label=\"#{p6_header}\" data-v=\"#{r[:buy_price_6]}\" title=\"目标息率 #{add_yield_tag}（#{r[:buy_method]}）\">#{format_num(r[:buy_price_6], 2)}<div class=\"code\">#{add_yield_tag}</div></td>"
  html << "<td class=\"right only-desktop#{hit7 ? ' price-hit' : ''}\" data-label=\"#{p7_header}\" data-v=\"#{r[:buy_price_7]}\" title=\"目标息率 #{heavy_yield_tag}（#{r[:buy_method]}）\">#{format_num(r[:buy_price_7], 2)}<div class=\"code\">#{heavy_yield_tag}</div></td>"
  html << "<td class=\"right only-mobile\" data-label=\"目标价\" data-v=\"#{r[:buy_price_5]}\"><div class=\"ladder-lines\"><span class=\"#{hit5 ? 'price-hit' : ''}\">首 #{format_num(r[:buy_price_5], 2)}<span style=\"color:#888\"> #{first_yield_tag}</span></span><span class=\"#{hit6 ? 'price-hit' : ''}\">加 #{format_num(r[:buy_price_6], 2)}<span style=\"color:#888\"> #{add_yield_tag}</span></span><span class=\"#{hit7 ? 'price-hit' : ''}\">重 #{format_num(r[:buy_price_7], 2)}<span style=\"color:#888\"> #{heavy_yield_tag}</span></span></div></td>"
  html << "</tr>\n"

  html << "<tr class=\"detail-row row-hidden\" data-for=\"#{key}\">"
  html << "<td class=\"detail\" colspan=\"10\">"
  html << "<div class=\"detail-card\">"
  html << "<div class=\"detail-top\">"
  html << "<div class=\"chart-card\">"
  html << "<div class=\"detail-title\">年度股息率 / DPS</div>"
  html << "<div class=\"detail-sub\">按报告期年度汇总，蓝柱是股息率，红线是每股派现(DPS)</div>"
  html << "<div class=\"chart-legend\"><span class=\"chart-legend-item\"><span class=\"chart-legend-bar\"></span>股息率</span><span class=\"chart-legend-item\"><span class=\"chart-legend-line\"></span>DPS</span></div>"
  html << "<div class=\"div-chart-scroll\">"
  html << "<div class=\"div-chart\" data-chart-code=\"#{r[:code]}\"></div>"
  html << "</div>"
  html << "</div>"
  html << "<div class=\"metrics-card\">"
  html << "<div class=\"detail-title\">关键指标</div>"
  html << "<div class=\"detail-sub\">展开后快速看你关心的估值、分红和财务数据</div>"
  html << "<div class=\"kv\">"
  html << "<div class=\"kv-item\"><b>分红率</b><span>#{format_pct(r[:dividend_payout_ratio], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>换手率</b><span>#{format_pct(r[:turnover_rate], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>总市值</b><span>#{format_yi(r[:market_cap], 1)}</span></div>"
  html << "<div class=\"kv-item\"><b>30日跌幅</b><span>#{format_pct(r[:drop_30d], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>有息负债率</b><span>#{format_pct(r[:interest_debt_ratio], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>PE</b><span>#{format_num(r[:pe_ttm], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>PB</b><span>#{format_num(r[:pb], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>ROE</b><span>#{format_pct(r[:roe_jq], 2)}</span></div>"
  html << "</div>"
  html << "</div>"
  html << "</div>"
  html << "</div>"
  html << "</td>"
  html << "</tr>\n"
end

html << <<~HTML
      </tbody>
    </table>
    </div>
  </div>

  <div class="card">
    <h1 style="font-size:16px;margin:0 0 8px 0;">半年内即将分红</h1>
    <div class="meta">按除权除息日正序 · 条数：#{upcoming.size}</div>
    <div class="table-wrap" id="captureDiv">
    <table id="t2">
      <thead>
        <tr>
          <th data-k="ex" data-t="str">除权除息日</th>
          <th data-k="name" data-t="str">股票</th>
          <th data-k="code" data-t="str">代码</th>
          <th class="right" data-k="cash" data-t="num">每股派现</th>
          <th class="right" data-k="y" data-t="num">股息率</th>
          <th data-k="p" data-t="str">进度</th>
          <th data-k="plan" data-t="str">方案</th>
        </tr>
      </thead>
      <tbody>
HTML

upcoming.each do |d|
  html << "<tr>"
  html << "<td data-v=\"#{d[:ex_dividend_date]}\">#{d[:ex_dividend_date]}</td>"
  html << "<td data-v=\"#{d[:name]}\">#{d[:name]}</td>"
  html << "<td data-v=\"#{d[:code]}\">#{d[:code]}</td>"
  html << "<td class=\"right\" data-v=\"#{d[:cash_dividend_per_share]}\">#{format_num(d[:cash_dividend_per_share], 4)}</td>"
  html << "<td class=\"right\" data-v=\"#{d[:dividend_yield_pct]}\">#{format_pct(d[:dividend_yield_pct], 2)}</td>"
  html << "<td data-v=\"#{d[:progress]}\">#{d[:progress]}</td>"
  html << "<td data-v=\"#{d[:plan_description]}\">#{d[:plan_description]}</td>"
  html << "</tr>\n"
end

html << <<~HTML
      </tbody>
    </table>
    </div>
  </div>

  <script>
    (function(){
      const dividendYearlyData = #{JSON.generate(rows_out.each_with_object({}) { |row, acc| acc[row[:code]] = row[:annual_dividends] })};
      function getVal(td, type){
        const v = td.getAttribute('data-v');
        if(v===null||v==='') return null;
        if(type==='num'){
          const n = Number(v);
          return Number.isFinite(n) ? n : null;
        }
        return String(v);
      }
      function getRowAttrVal(tr, key, type){
        const v = tr.getAttribute('data-' + key);
        if(v===null||v==='') return null;
        if(type==='num'){
          const n = Number(v);
          return Number.isFinite(n) ? n : null;
        }
        return String(v);
      }
      function sortTable(table, key, type, dir){
        const tbody = table.querySelector('tbody');
        const mains = Array.from(tbody.querySelectorAll('tr.main'));
        const idx = Array.from(table.querySelectorAll('thead th')).findIndex(th => th.getAttribute('data-k')===key);
        const items = mains.map(m => {
          const id = m.getAttribute('data-id');
          const detail = tbody.querySelector(`tr.detail-row[data-for="${id}"]`);
          return { m, d: detail };
        });
        items.sort((a,b)=>{
          const av = idx >= 0 ? getVal(a.m.children[idx], type) : getRowAttrVal(a.m, key, type);
          const bv = idx >= 0 ? getVal(b.m.children[idx], type) : getRowAttrVal(b.m, key, type);
          if(av===null && bv===null) return 0;
          if(av===null) return 1;
          if(bv===null) return -1;
          if(type==='num') return av-bv;
          return av.localeCompare(bv,'zh');
        });
        if(dir==='desc') items.reverse();
        items.forEach(x=>{
          tbody.appendChild(x.m);
          if(x.d) tbody.appendChild(x.d);
        });
      }
      function bind(table){
        const ths = table.querySelectorAll('thead th[data-k]');
        ths.forEach(th=>{
          th.addEventListener('click', ()=>{
            const key = th.getAttribute('data-k');
            const type = th.getAttribute('data-t') || 'str';
            const cur = th.getAttribute('data-dir') || '';
            const dir = cur==='asc' ? 'desc' : 'asc';
            ths.forEach(x=>x.removeAttribute('data-dir'));
            th.setAttribute('data-dir', dir);
            sortTable(table, key, type, dir);
          });
        });
      }
      function escapeHtml(s){
        return String(s)
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('\"', '&quot;')
          .replaceAll(\"'\", '&#39;');
      }
      function formatPct(v){
        const n = Number(v);
        return Number.isFinite(n) ? `${n.toFixed(2)}%` : '';
      }
      function formatNum(v, precision){
        const n = Number(v);
        return Number.isFinite(n) ? n.toFixed(precision) : '';
      }
      function compactYearLabel(year, count){
        const y = String(year || '');
        if(count >= 14 && y.length >= 4) return y.slice(2);
        return y;
      }
      function buildDpsLine(items, count, plotHeight){
        const maxCash = items.reduce((m, x) => {
          const v = Number(x.cash_dividend);
          return Number.isFinite(v) ? Math.max(m, v) : m;
        }, 0);
        if(maxCash <= 0) return '';
        const viewWidth = Math.max(count * 100, 100);
        const step = viewWidth / count;
        const points = items.map((item, idx) => {
          const cashVal = Number(item.cash_dividend);
          const x = (idx * step) + (step / 2);
          const y = Number.isFinite(cashVal) ? (plotHeight * (1 - (cashVal / maxCash))) : plotHeight;
          return { x, y, cashVal };
        });
        const path = points.map((p, idx) => `${idx === 0 ? 'M' : 'L'} ${p.x.toFixed(2)} ${p.y.toFixed(2)}`).join(' ');
        const circles = points.map(p => `<circle class="div-line-dot" cx="${p.x.toFixed(2)}" cy="${p.y.toFixed(2)}" r="${count >= 16 ? 2.4 : 3.2}"></circle>`).join('');
        return `<svg class="div-line-svg" viewBox="0 0 ${viewWidth} ${plotHeight}" preserveAspectRatio="none" aria-hidden="true"><path class="div-line-path" d="${path}"></path>${circles}</svg>`;
      }
      function renderDividendChart(container){
        if(!container || container.getAttribute('data-rendered') === '1') return;
        const code = container.getAttribute('data-chart-code');
        const items = Array.isArray(dividendYearlyData[code]) ? dividendYearlyData[code] : [];
        if(!items.length){
          container.innerHTML = '<div class="chart-empty">暂无年度股息率数据</div>';
          container.setAttribute('data-rendered', '1');
          return;
        }
        const maxYield = items.reduce((m, x) => {
          const v = Number(x.dividend_yield);
          return Number.isFinite(v) ? Math.max(m, v) : m;
        }, 0);
        const safeMax = maxYield > 0 ? maxYield : 1;
        const count = items.length;
        const gapPx = count >= 18 ? 1 : (count >= 14 ? 2 : 4);
        const barWidthPx = count >= 18 ? 8 : (count >= 14 ? 10 : 14);
        const plotHeight = count >= 18 ? 96 : 110;
        container.style.setProperty('--chart-count', String(count));
        container.style.setProperty('--chart-gap', `${gapPx}px`);
        container.style.setProperty('--bar-width', `${barWidthPx}px`);
        const colsHtml = items.map(item => {
          const yieldVal = Number(item.dividend_yield);
          const cashVal = Number(item.cash_dividend);
          const height = Number.isFinite(yieldVal) ? Math.max((yieldVal / safeMax) * 100, yieldVal > 0 ? 3 : 0) : 0;
          const yearLabel = compactYearLabel(item.year, count);
          return `
            <div class="div-col" title="${escapeHtml(item.year)} 年 | 股息率 ${escapeHtml(formatPct(yieldVal))} | 每股派现 ${escapeHtml(formatNum(cashVal, 4))}">
              <div class="div-yield">${escapeHtml(formatPct(yieldVal))}</div>
              <div class="div-bar-wrap"><div class="div-bar" style="height:${height}%"></div></div>
              <div class="div-year">${escapeHtml(yearLabel)}</div>
            </div>
          `;
        }).join('');
        container.innerHTML = colsHtml + buildDpsLine(items, count, plotHeight);
        container.setAttribute('data-rendered', '1');
      }
      const t = document.getElementById('t');
      const t2 = document.getElementById('t2');
      bind(t);
      bind(t2);
      sortTable(t, 'needDrop', 'num', 'asc');

      const q = document.getElementById('q');
      const catSel = document.getElementById('catSel');
      const wlOnly = document.getElementById('wlOnly');
      const mains = Array.from(document.querySelectorAll('#t tbody tr.main'));
      function applyFilters(){
        const s = (q && q.value ? q.value : '').trim().toLowerCase();
        const catV = (catSel && catSel.value ? catSel.value : '').trim();
        const onlyWl = !!(wlOnly && wlOnly.checked);
        let catType = '';
        let catBig = '';
        let catSub = '';
        if(catV){
          const parts = catV.split(':');
          catType = parts[0] || '';
          catBig = parts[1] || '';
          catSub = parts[2] || '';
        }
        mains.forEach(r=>{
          const id = r.getAttribute('data-id');
          const detail = document.querySelector(`#t tbody tr.detail-row[data-for="${id}"]`);

          let ok = true;
          if(onlyWl && r.getAttribute('data-wl') !== '1') ok = false;
          if(ok && catV){
            if(catType === 'big'){
              if(r.getAttribute('data-wlbig') !== catBig) ok = false;
            } else if(catType === 'sub'){
              if(r.getAttribute('data-wlbig') !== catBig) ok = false;
              if(r.getAttribute('data-wlsub') !== catSub) ok = false;
            }
          }
          if(ok && s){
            const text = r.children[0].textContent.trim().toLowerCase();
            if(!text.includes(s)) ok = false;
          }

          if(ok){
            r.classList.remove('row-hidden');
          } else {
            r.classList.add('row-hidden');
            if(detail) detail.classList.add('row-hidden');
          }
        });
      }
      if(q) q.addEventListener('input', applyFilters);
      if(catSel) catSel.addEventListener('change', applyFilters);
      if(wlOnly) wlOnly.addEventListener('change', applyFilters);
      applyFilters();

      document.querySelectorAll('#t tbody tr.main').forEach(tr=>{
        tr.addEventListener('click', ()=>{
          const id = tr.getAttribute('data-id');
          const detail = document.querySelector(`#t tbody tr.detail-row[data-for="${id}"]`);
          if(!detail) return;
          const willOpen = detail.classList.contains('row-hidden');
          detail.classList.toggle('row-hidden');
          if(willOpen){
            renderDividendChart(detail.querySelector('[data-chart-code]'));
          }
        });
      });

    })();
  </script>
</body>
</html>
HTML

File.write(OUT_HTML, html)

payload = {
  generated_date_beijing: generated_at_bj,
  source_yml: File.basename(IN_YML),
  filter: { dividend_yield_gt: nil, default_whitelist_only: true },
  whitelist_big_order: WHITELIST_BIG_ORDER,
  whitelist_sub_by_big: WHITELIST_SUB_BY_BIG,
  stocks: rows_out.map { |x| x.reject { |k, _| k == :id } },
  upcoming_dividends_6m: upcoming
}
File.write(OUT_YML, payload.to_yaml)

puts "written #{OUT_HTML}"
puts "written #{OUT_YML}"
