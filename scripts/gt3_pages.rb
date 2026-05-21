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

def format_score_half(v)
  return '' if v.nil?
  x = v.to_f
  return '' unless x.finite?
  r = (x * 2.0).round / 2.0
  ((r - r.round).abs < 1e-9) ? r.round.to_s : format('%.1f', r)
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

has_consecutive_dividend_years = Stock.column_names.include?('consecutive_dividend_years')
stock_pluck_keys = [
  :id, :code, :name,
  :buy_score, :avg_dividend_yield_3y, :dividend_yield
]
stock_pluck_keys << :consecutive_dividend_years if has_consecutive_dividend_years
stock_pluck_keys.concat(
  [
    :dividend_cash_per_share_latest_year, :current_price,
    :pe_percentile, :pb_percentile, :price_position,
    :roe_jq, :drop_30d, :asset_liability_ratio, :fcf_yield
  ]
)

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
        buy_score: v[:buy_score]&.to_f,
        avg_dividend_yield_3y: v[:avg_dividend_yield_3y]&.to_f,
        dividend_yield: v[:dividend_yield]&.to_f,
        consecutive_dividend_years: has_consecutive_dividend_years ? v[:consecutive_dividend_years]&.to_i : nil,
        dividend_cash_per_share_latest_year: v[:dividend_cash_per_share_latest_year]&.to_f,
        current_price: v[:current_price]&.to_f,
        pe_percentile: v[:pe_percentile]&.to_f,
        pb_percentile: v[:pb_percentile]&.to_f,
        price_position: v[:price_position]&.to_f,
        roe_jq: v[:roe_jq]&.to_f,
        drop_30d: v[:drop_30d]&.to_f,
        asset_liability_ratio: v[:asset_liability_ratio]&.to_f,
        fcf_yield: v[:fcf_yield]&.to_f
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
      buy5 = (dps && dps > 0) ? (dps / 0.05) : nil
      buy6 = (dps && dps > 0) ? (dps / 0.06) : nil
      buy7 = (dps && dps > 0) ? (dps / 0.07) : nil
      drop5 = (buy5 && price && price > 0) ? ((1.0 - (buy5 / price)) * 100.0) : nil
      drop6 = (buy6 && price && price > 0) ? ((1.0 - (buy6 / price)) * 100.0) : nil
      drop7 = (buy7 && price && price > 0) ? ((1.0 - (buy7 / price)) * 100.0) : nil

      row.merge(m).merge(
        categories: cats,
        is_core: core_hits.any?,
        core_categories: core_hits,
        buy_price_5: buy5,
        buy_price_6: buy6,
        buy_price_7: buy7,
        drop_to_5: drop5,
        drop_to_6: drop6,
        drop_to_7: drop7
      )
    end

rows_out.sort_by! do |x|
  [-(x[:buy_score] || 0).to_f, -(x[:dividend_yield] || 0).to_f, x[:code]]
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
    @media (max-width: 640px){
      body{padding:12px}
      .card{padding:12px}
      th,td{padding:6px 8px}
      table{font-size:11px}
      h1{font-size:18px}
      .detail-card{padding:10px}
      .kv-item{font-size:11px;padding:6px 9px}
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
          <th data-k="namecode" data-t="str">名称/代码</th>
          <th class="right" data-k="price" data-t="num">最新价</th>
          <th class="right" data-k="avg3y" data-t="num">3年均息率</th>
          <th class="right" data-k="dy" data-t="num">最新股息率</th>
          <th class="right" data-k="cdy" data-t="num">连续分红(年)</th>
          <th class="right" data-k="p5" data-t="num">首仓价(5%)</th>
          <th class="right" data-k="p6" data-t="num">加仓价(6%)</th>
          <th class="right" data-k="p7" data-t="num">重仓价(7%)</th>
          <th class="right" data-k="score" data-t="num">评分</th>
        </tr>
      </thead>
      <tbody>
HTML

rows_out.each do |r|
  key = Digest::MD5.hexdigest("#{r[:code]}|#{r[:name]}")
  namecode = "#{r[:name]} #{r[:code]}"
  cur_price = r[:current_price].to_f
  cur_price_ok = r[:current_price] && cur_price.finite?

  html << "<tr class=\"row-click main\" data-id=\"#{key}\" data-core=\"#{r[:is_core] ? 1 : 0}\">"
  html << "<td class=\"name-code\" data-v=\"#{namecode}\">#{r[:name]}<div class=\"code\">#{r[:code]}</div></td>"
  html << "<td class=\"right\" data-v=\"#{r[:current_price]}\">#{format_num(r[:current_price], 2)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:avg_dividend_yield_3y]}\">#{format_pct(r[:avg_dividend_yield_3y], 2)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:dividend_yield]}\">#{format_pct(r[:dividend_yield], 2)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:consecutive_dividend_years]}\">#{r[:consecutive_dividend_years].to_i if r[:consecutive_dividend_years]}</td>"
  hit5 = cur_price_ok && r[:buy_price_5] && cur_price <= r[:buy_price_5].to_f
  hit6 = cur_price_ok && r[:buy_price_6] && cur_price <= r[:buy_price_6].to_f
  hit7 = cur_price_ok && r[:buy_price_7] && cur_price <= r[:buy_price_7].to_f
  html << "<td class=\"right#{hit5 ? ' price-hit' : ''}\" data-v=\"#{r[:buy_price_5]}\">#{format_num(r[:buy_price_5], 2)}</td>"
  html << "<td class=\"right#{hit6 ? ' price-hit' : ''}\" data-v=\"#{r[:buy_price_6]}\">#{format_num(r[:buy_price_6], 2)}</td>"
  html << "<td class=\"right#{hit7 ? ' price-hit' : ''}\" data-v=\"#{r[:buy_price_7]}\">#{format_num(r[:buy_price_7], 2)}</td>"
  html << "<td class=\"right\" data-v=\"#{r[:buy_score]}\">#{format_score_half(r[:buy_score])}</td>"
  html << "</tr>\n"

  html << "<tr class=\"detail-row row-hidden\" data-for=\"#{key}\">"
  html << "<td class=\"detail\" colspan=\"9\">"
  html << "<div class=\"detail-card\">"
  html << "<div class=\"kv\">"
  html << "<div class=\"kv-item\"><b>最新年度DPS</b><span>#{format_num(r[:dividend_cash_per_share_latest_year], 4)}</span></div>"
  html << "<div class=\"kv-item\"><b>PE分位</b><span>#{format_ratio_pct(r[:pe_percentile], 0)}</span></div>"
  html << "<div class=\"kv-item\"><b>PB分位</b><span>#{format_ratio_pct(r[:pb_percentile], 0)}</span></div>"
  html << "<div class=\"kv-item\"><b>价格分位</b><span>#{format_ratio_pct(r[:price_position], 0)}</span></div>"
  html << "<div class=\"kv-item\"><b>ROE</b><span>#{format_pct(r[:roe_jq], 1)}</span></div>"
  html << "<div class=\"kv-item\"><b>资产负债率</b><span>#{format_pct(r[:asset_liability_ratio], 1)}</span></div>"
  html << "<div class=\"kv-item\"><b>FCF收益率</b><span>#{format_pct(r[:fcf_yield], 2)}</span></div>"
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
          const av = getVal(a.m.children[idx], type);
          const bv = getVal(b.m.children[idx], type);
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
      sortTable(t, 'score', 'num', 'desc');

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
