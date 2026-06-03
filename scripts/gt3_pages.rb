require 'yaml'
require 'date'
require 'time'
require 'fileutils'
require 'digest'

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

      dy = m[:dividend_yield]
      next unless dy && dy > 3.0

      dps = m[:dividend_cash_per_share_latest_year]
      price = m[:current_price]
      min3y = m[:min_dividend_yield_3y]
      buy5 = (price && price > 0 && min3y && min3y > 0) ? (price * (min3y / 5.0)) : nil
      buy6 = (price && price > 0 && min3y && min3y > 0) ? (price * (min3y / 6.0)) : nil
      buy7 = (price && price > 0 && min3y && min3y > 0) ? (price * (min3y / 7.0)) : nil
      drop5 = (buy5 && price && price > 0) ? ((1.0 - (buy5 / price)) * 100.0) : nil
      drop6 = (buy6 && price && price > 0) ? ((1.0 - (buy6 / price)) * 100.0) : nil
      drop7 = (buy7 && price && price > 0) ? ((1.0 - (buy7 / price)) * 100.0) : nil
      need_drop5 = drop5 ? [drop5.to_f, 0.0].max : nil

      row.merge(m).merge(
        categories: cats,
        is_core: core_hits.any?,
        core_categories: core_hits,
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
  [(x[:need_drop_to_5].nil? ? 1_000_000.0 : x[:need_drop_to_5].to_f), -(x[:avg_dividend_yield_3y] || 0).to_f, x[:code]]
end

consecutive_map = {}
begin
  conn = ActiveRecord::Base.connection
  ids = rows_out.map { |x| x[:id] }.compact.uniq
  if ids.any? && conn.data_source_exists?('dividends')
    sums =
      Dividend
        .where(stock_id: ids)
        .group(:stock_id)
        .group(Arel.sql('EXTRACT(YEAR FROM report_date)'))
        .sum(:cash_dividend)

    per_year_by_sid = Hash.new { |h, k| h[k] = Hash.new(0.0) }
    sums.each do |(sid, year), cash|
      y = year.to_i
      per_year_by_sid[sid][y] = cash.to_f
    end

    per_year_by_sid.each do |sid, per_year|
      years = per_year.select { |_, v| v.to_f > 0.0 }.keys
      next if years.empty?
      y = years.max
      n = 0
      while per_year[y - n].to_f > 0.0
        n += 1
      end
      consecutive_map[sid] = n
    end
  end
rescue StandardError
  consecutive_map = {}
end

rows_out.each do |r|
  next if r[:consecutive_dividend_years] && r[:consecutive_dividend_years].to_i > 0
  v = consecutive_map[r[:id]]
  r[:consecutive_dividend_years] = v if v && v.to_i > 0
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
    .btn{appearance:none;border:1px solid #ddd;background:#fff;border-radius:8px;padding:8px 10px;font-size:12px;color:#111}
    .btn:active{transform:scale(0.99)}
    .check{display:inline-flex;align-items:center;gap:6px;border:1px solid #ddd;background:#fff;border-radius:999px;padding:8px 10px;font-size:12px;color:#111}
    .check input{width:14px;height:14px}
    .row-click{cursor:pointer}
    .detail{white-space:normal}
    .price-hit{font-weight:700;color:#c1121f}
    .detail-card{background:#fafafe;border:1px solid #eee;border-radius:10px;padding:12px}
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
    }
  </style>
</head>
<body>
  <div class="card">
    <h1>GT3 红利列表（股息率&gt;3%）</h1>
    <div class="meta">生成日期（北京时间）：#{generated_at_bj} · 行数：#{rows_out.size}</div>
    <div style="display:flex;gap:10px;flex-wrap:wrap;align-items:center">
      <input id="q" class="search" placeholder="搜索 名称/代码" />
      <label class="check"><input id="coreOnly" type="checkbox" />核心</label>
      <button id="btnSaveMain" type="button" class="btn">保存为图片</button>
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
          <th class="right" data-k="payout" data-t="num"><span class="h-desktop">分红率</span><span class="h-mobile">分红率</span></th>
          <th class="right" data-k="cdy" data-t="num"><span class="h-desktop">连续分红(年)</span><span class="h-mobile">连续分红</span></th>
          <th class="right" data-k="needDrop" data-t="num"><span class="h-desktop">需跌幅(首)</span><span class="h-mobile">需跌幅</span></th>
          <th class="right only-desktop" data-k="p5" data-t="num">首仓价(5%)</th>
          <th class="right only-desktop" data-k="p6" data-t="num">加仓价(6%)</th>
          <th class="right only-desktop" data-k="p7" data-t="num">重仓价(7%)</th>
          <th class="right only-mobile" data-k="p5" data-t="num"><span class="h-desktop">目标价</span><span class="h-mobile">5/6/7</span></th>
        </tr>
      </thead>
      <tbody>
HTML

rows_out.each do |r|
  key = Digest::MD5.hexdigest("#{r[:code]}|#{r[:name]}")
  namecode = "#{r[:name]} #{r[:code]}"
  cur_price = r[:current_price].to_f
  cur_price_ok = r[:current_price] && cur_price.finite?

  html << "<tr class=\"row-click main\" data-id=\"#{key}\" data-core=\"#{r[:is_core] ? 1 : 0}\" data-avg3y=\"#{r[:avg_dividend_yield_3y]}\" data-min3y=\"#{r[:min_dividend_yield_3y]}\">"
  html << "<td class=\"name-code\" data-label=\"名称/代码\" data-v=\"#{namecode}\">#{r[:name]}<div class=\"code\">#{r[:code]}</div></td>"
  html << "<td class=\"right\" data-label=\"最新价\" data-v=\"#{r[:current_price]}\">#{format_num(r[:current_price], 2)}</td>"
  html << "<td class=\"right\" data-label=\"股息率\" data-v=\"#{r[:dividend_yield]}\"><div class=\"yield-lines\"><span><span style=\"color:#666\">新</span> #{format_pct(r[:dividend_yield], 2)}</span><span><span style=\"color:#666\">均</span> #{format_pct(r[:avg_dividend_yield_3y], 2)}</span><span><span style=\"color:#666\">低</span> #{format_pct(r[:min_dividend_yield_3y], 2)}</span></div></td>"
  html << "<td class=\"right\" data-label=\"分红率\" data-v=\"#{r[:dividend_payout_ratio]}\">#{format_pct(r[:dividend_payout_ratio], 0)}</td>"
  html << "<td class=\"right\" data-label=\"连续分红(年)\" data-v=\"#{r[:consecutive_dividend_years]}\">#{r[:consecutive_dividend_years].to_i if r[:consecutive_dividend_years]}</td>"
  html << "<td class=\"right\" data-label=\"需跌幅\" data-v=\"#{r[:need_drop_to_5]}\">#{format_pct(r[:need_drop_to_5], 2)}</td>"
  hit5 = cur_price_ok && r[:buy_price_5] && cur_price <= r[:buy_price_5].to_f
  hit6 = cur_price_ok && r[:buy_price_6] && cur_price <= r[:buy_price_6].to_f
  hit7 = cur_price_ok && r[:buy_price_7] && cur_price <= r[:buy_price_7].to_f
  html << "<td class=\"right only-desktop#{hit5 ? ' price-hit' : ''}\" data-label=\"首仓价(5%)\" data-v=\"#{r[:buy_price_5]}\">#{format_num(r[:buy_price_5], 2)}</td>"
  html << "<td class=\"right only-desktop#{hit6 ? ' price-hit' : ''}\" data-label=\"加仓价(6%)\" data-v=\"#{r[:buy_price_6]}\">#{format_num(r[:buy_price_6], 2)}</td>"
  html << "<td class=\"right only-desktop#{hit7 ? ' price-hit' : ''}\" data-label=\"重仓价(7%)\" data-v=\"#{r[:buy_price_7]}\">#{format_num(r[:buy_price_7], 2)}</td>"
  html << "<td class=\"right only-mobile\" data-label=\"目标价\" data-v=\"#{r[:buy_price_5]}\"><div class=\"ladder-lines\"><span class=\"#{hit5 ? 'price-hit' : ''}\">首 #{format_num(r[:buy_price_5], 2)}</span><span class=\"#{hit6 ? 'price-hit' : ''}\">加 #{format_num(r[:buy_price_6], 2)}</span><span class=\"#{hit7 ? 'price-hit' : ''}\">重 #{format_num(r[:buy_price_7], 2)}</span></div></td>"
  html << "</tr>\n"

  html << "<tr class=\"detail-row row-hidden\" data-for=\"#{key}\">"
  html << "<td class=\"detail\" colspan=\"10\">"
  html << "<div class=\"detail-card\">"
  html << "<div class=\"kv\">"
  html << "<div class=\"kv-item\"><b>换手率</b><span>#{format_pct(r[:turnover_rate], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>总市值</b><span>#{format_yi(r[:market_cap], 1)}</span></div>"
  html << "<div class=\"kv-item\"><b>成交量</b><span>#{format_wanshou(r[:volume], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>均价</b><span>#{r[:avg_price] ? "¥#{format_num(r[:avg_price], 2)}" : ''}</span></div>"
  html << "<div class=\"kv-item\"><b>最新年度DPS</b><span>#{format_num(r[:dividend_cash_per_share_latest_year], 4)}</span></div>"
  html << "<div class=\"kv-item\"><b>分红率</b><span>#{format_pct(r[:dividend_payout_ratio], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>30日跌幅</b><span>#{format_pct(r[:drop_30d], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>30d分位</b><span>#{format_ratio_pct(r[:pos_30d], 0)}</span></div>"
  html << "<div class=\"kv-item\"><b>市盈率(TTM)</b><span>#{format_num(r[:pe_ttm], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>估值区域</b><span>#{r[:valuation_label].to_s}</span></div>"
  html << "<div class=\"kv-item\"><b>PE分位</b><span>#{format_ratio_pct(r[:pe_percentile], 0)}</span></div>"
  html << "<div class=\"kv-item\"><b>PEG</b><span>#{format_num(r[:peg], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>PEG等级</b><span>#{peg_level_label(r[:peg_level])}</span></div>"
  html << "<div class=\"kv-item\"><b>净利同比</b><span>#{format_pct(r[:net_profit_yoy], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>财报期</b><span>#{r[:finance_report_date].to_s}</span></div>"
  html << "<div class=\"kv-item\"><b>市净率</b><span>#{format_num(r[:pb], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>PB分位</b><span>#{format_ratio_pct(r[:pb_percentile], 0)}</span></div>"
  html << "<div class=\"kv-item\"><b>资产负债率</b><span>#{format_pct(r[:asset_liability_ratio], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>有息负债率</b><span>#{format_pct(r[:interest_debt_ratio], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>自由现金流</b><span>#{format_pct(r[:fcf_yield], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>FCF/EV</b><span>#{format_pct(r[:fcf_ev], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>FCF</b><span>#{format_yi(r[:fcff_back], 1)}</span></div>"
  html << "<div class=\"kv-item\"><b>ROE(加权)</b><span>#{format_pct(r[:roe_jq], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>近5年均值≥12%</b><span>#{r[:roe_5y_avg_ge_12] ? '是' : '否'}</span></div>"
  html << "<div class=\"kv-item\"><b>近5年最低≥8%</b><span>#{r[:roe_5y_min_ge_8] ? '是' : '否'}</span></div>"
  html << "<div class=\"kv-item\"><b>近5年均值</b><span>#{format_pct(r[:roe_5y_avg], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>近5年最低</b><span>#{format_pct(r[:roe_5y_min], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>总股本</b><span>#{format_yigu(r[:total_shares], 2)}</span></div>"
  html << "<div class=\"kv-item\"><b>连续分红</b><span>#{r[:consecutive_dividend_years] ? "#{r[:consecutive_dividend_years]}年" : ''}</span></div>"
  html << "<div class=\"kv-item kv-full\"><b>分类</b><span>#{Array(r[:categories]).join(' / ')}</span></div>"
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
    <div style="margin:10px 0 0 0;">
      <button id="btnSaveDiv" type="button" class="btn">保存为图片</button>
    </div>
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

  <script src="https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js"></script>
  <script>
    (function(){
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
      const t = document.getElementById('t');
      const t2 = document.getElementById('t2');
      bind(t);
      bind(t2);
      sortTable(t, 'needDrop', 'num', 'asc');

      const q = document.getElementById('q');
      const coreOnly = document.getElementById('coreOnly');
      const mains = Array.from(document.querySelectorAll('#t tbody tr.main'));
      function applyFilters(){
        const s = (q && q.value ? q.value : '').trim().toLowerCase();
        const onlyCore = !!(coreOnly && coreOnly.checked);
        mains.forEach(r=>{
          const id = r.getAttribute('data-id');
          const detail = document.querySelector(`#t tbody tr.detail-row[data-for="${id}"]`);

          let ok = true;
          if(onlyCore && r.getAttribute('data-core') !== '1') ok = false;
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
      if(coreOnly) coreOnly.addEventListener('change', applyFilters);

      document.querySelectorAll('#t tbody tr.main').forEach(tr=>{
        tr.addEventListener('click', ()=>{
          const id = tr.getAttribute('data-id');
          const detail = document.querySelector(`#t tbody tr.detail-row[data-for="${id}"]`);
          if(!detail) return;
          detail.classList.toggle('row-hidden');
        });
      });

      function saveAsImage(targetId, fileName){
        const el = document.getElementById(targetId);
        if(!el || !window.html2canvas) return;
        html2canvas(el, { backgroundColor: '#ffffff', scale: 2 }).then(canvas=>{
          const a = document.createElement('a');
          a.href = canvas.toDataURL('image/png');
          a.download = fileName;
          a.click();
        });
      }

      const btnMain = document.getElementById('btnSaveMain');
      if(btnMain){
        btnMain.addEventListener('click', ()=> saveAsImage('captureTable', 'gt3_#{generated_at_bj}.png'));
      }
      const btnDiv = document.getElementById('btnSaveDiv');
      if(btnDiv){
        btnDiv.addEventListener('click', ()=> saveAsImage('captureDiv', 'gt3_dividend_#{generated_at_bj}.png'));
      }
    })();
  </script>
</body>
</html>
HTML

File.write(OUT_HTML, html)

payload = {
  generated_date_beijing: generated_at_bj,
  source_yml: File.basename(IN_YML),
  filter: { dividend_yield_gt: 3.0 },
  stocks: rows_out.map { |x| x.reject { |k, _| k == :id } },
  upcoming_dividends_6m: upcoming
}
File.write(OUT_YML, payload.to_yaml)

puts "written #{OUT_HTML}"
puts "written #{OUT_YML}"
