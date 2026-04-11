require 'date'
require 'sinatra'
require 'sinatra/reloader' if development?
require_relative 'models'
require_relative 'services/valuation_history_syncer'

set :bind, '0.0.0.0'
set :port, 4567

get '/' do
  allowed_sort_fields = %w[
    name code current_price expected_dividend_yield dividend_yield
    turnover_rate volume pe_ttm pb pb_level pb_percentile total_shares
    pos_30d pos_1y pos_3y pos_5y price_position
  ]
  
  only_div5y = params[:only_div5y].to_s == '1'
  include_category_ids = parse_id_list(params[:include_category_ids])
  exclude_category_ids = parse_id_list(params[:exclude_category_ids])
  include_pb_levels = parse_id_list(params[:include_pb_levels]).select { |x| x >= 1 && x <= 6 }
  exclude_pb_levels = parse_id_list(params[:exclude_pb_levels]).select { |x| x >= 1 && x <= 6 }
  include_pb_percentile_levels = parse_id_list(params[:include_pb_percentile_levels]).select { |x| x >= 1 && x <= 4 }
  exclude_pb_percentile_levels = parse_id_list(params[:exclude_pb_percentile_levels]).select { |x| x >= 1 && x <= 4 }

  default_sorts = [{ field: 'expected_dividend_yield', order: 'desc' }]
  sorts = parse_sorts_param(params[:sort], default_sorts, allowed_sort_fields)

  if (remove_include = params[:remove_include_category_id].to_s.strip).size > 0
    include_category_ids = include_category_ids.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_category_id].to_s.strip).size > 0
    exclude_category_ids = exclude_category_ids.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_include = params[:remove_include_pb_level].to_s.strip).size > 0
    include_pb_levels = include_pb_levels.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_pb_level].to_s.strip).size > 0
    exclude_pb_levels = exclude_pb_levels.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_include = params[:remove_include_pb_percentile_level].to_s.strip).size > 0
    include_pb_percentile_levels = include_pb_percentile_levels.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_pb_percentile_level].to_s.strip).size > 0
    exclude_pb_percentile_levels = exclude_pb_percentile_levels.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_sort = params[:remove_sort].to_s.strip).size > 0
    sorts = sorts.reject { |s| s[:field] == remove_sort }
    sorts = default_sorts if sorts.empty?
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end
  if params[:clear_sorts].to_s == '1'
    sorts = default_sorts
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  base_scope = Stock.includes(:categories)
  if only_div5y
    base_scope = base_scope.where(has_dividend_5y: true)
  end
  if include_category_ids.any?
    base_scope = base_scope.joins(:categorizations).where(categorizations: { category_id: include_category_ids }).distinct
  end
  if exclude_category_ids.any?
    excluded = Stock.joins(:categorizations).where(categorizations: { category_id: exclude_category_ids }).select(:id)
    base_scope = base_scope.where.not(id: excluded)
  end
  if include_pb_levels.any?
    base_scope = base_scope.where(pb_level: include_pb_levels)
  end
  if exclude_pb_levels.any?
    base_scope = base_scope.where.not(pb_level: exclude_pb_levels)
  end
  if include_pb_percentile_levels.any?
    base_scope = base_scope.where(pb_percentile_level: include_pb_percentile_levels)
  end
  if exclude_pb_percentile_levels.any?
    base_scope = base_scope.where.not(pb_percentile_level: exclude_pb_percentile_levels)
  end
  sorts.each do |s|
    if s[:field] == 'pe_ttm' && s[:order] == 'asc'
      base_scope = base_scope.where('pe_ttm > 0')
    end
  end

  order_sql = sorts.map { |s| "#{s[:field]} #{s[:order]} NULLS LAST" }.join(', ')
  @stocks = base_scope.order(order_sql)

  @categories = Category.joins(:categorizations).group('categories.id').order('count(categorizations.id) desc')
  @include_category_ids = include_category_ids
  @exclude_category_ids = exclude_category_ids
  @included_categories = include_category_ids.empty? ? [] : Category.where(id: include_category_ids)
  @excluded_categories = exclude_category_ids.empty? ? [] : Category.where(id: exclude_category_ids)
  @include_pb_levels = include_pb_levels
  @exclude_pb_levels = exclude_pb_levels
  @include_pb_percentile_levels = include_pb_percentile_levels
  @exclude_pb_percentile_levels = exclude_pb_percentile_levels
  @sorts = sorts
  @sort_param = serialize_sorts_param(sorts)
  @only_div5y = only_div5y
  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  
  erb :index
end

get '/macro' do
  @cn_10y_latest = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  @cn_10y_series = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :asc).pluck(:date, :yield_pct)
  erb :macro
end

get '/kb' do
  erb :kb_index
end

get '/kb/pb' do
  erb :kb_pb
end

get '/stocks/:id' do
  @stock = Stock.includes(:categories).find(params[:id])
  from_date = Date.today << 120
  need_val = @stock.price_histories.where('date >= ?', Date.today - 365).where(pb: nil).exists?
  if need_val
    ValuationHistorySyncer.new(scope: Stock.where(id: @stock.id), years: 10, sleep_range: nil).sync
  end
  # 价格走势（取最近 10 年），按日期升序用于绘图
  @price_histories = @stock.price_histories.where('date >= ?', from_date).order(date: :asc)
  # 分红历史，按报告期降序展示
  @dividends = @stock.dividends.order(report_date: :desc)
  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  
  erb :show
end

helpers do
  def parse_id_list(value)
    return [] if value.nil?
    arr =
      if value.is_a?(Array)
        value
      else
        value.to_s.split(',').map(&:strip)
      end
    arr.map { |x| x.to_i }.select { |x| x > 0 }.uniq
  end

  def parse_sorts_param(raw, default_sorts, allowed_fields)
    tokens = raw.to_s.split(',').map(&:strip).reject(&:empty?)
    return default_sorts if tokens.empty?

    out = []
    tokens.each do |tok|
      field, order = tok.split(':', 2)
      next unless allowed_fields.include?(field)
      order = order.to_s.downcase
      order = 'desc' unless %w[asc desc].include?(order)
      next if out.any? { |x| x[:field] == field }
      out << { field: field, order: order }
    end

    out.empty? ? default_sorts : out
  end

  def serialize_sorts_param(sorts)
    Array(sorts).map { |s| "#{s[:field]}:#{s[:order]}" }.join(',')
  end

  def build_query(params_hash)
    Rack::Utils.build_query(params_hash.reject { |_, v| v.nil? || v.to_s.empty? })
  end

  def sort_label(field)
    {
      'name' => '股票名称',
      'code' => '代码',
      'current_price' => '最新价',
      'expected_dividend_yield' => '预期股息率',
      'dividend_yield' => '历史股息率',
      'turnover_rate' => '换手率',
      'volume' => '成交量',
      'pe_ttm' => 'PE(TTM)',
      'pb' => 'PB',
      'pb_level' => 'PB等级',
      'pb_percentile' => 'PB历史分位',
      'total_shares' => '总股本',
      'pos_30d' => '30d位置',
      'pos_1y' => '1y位置',
      'pos_3y' => '3y位置',
      'pos_5y' => '5y位置',
      'price_position' => '全量位置'
    }[field] || field
  end

  def format_ratio_percent(value)
    return '-' if value.nil?
    "#{format_decimal(value.to_f * 100.0, 0)}%"
  end

  def pb_level_label(level)
    case level.to_i
    when 1 then '破净'
    when 2 then '低估'
    when 3 then '合理估值'
    when 4 then '成长溢价'
    when 5 then '高估'
    when 6 then '泡沫区'
    else
      '-'
    end
  end

  def pb_percentile_level_label(level)
    case level.to_i
    when 1 then '历史低位'
    when 2 then '偏低'
    when 3 then '偏高'
    when 4 then '历史高位'
    else
      '-'
    end
  end

  def format_decimal(value, precision = 2)
    return '-' if value.nil?
    sprintf("%.#{precision}f", value)
  end

  def format_percent(value)
    return '-' if value.nil?
    "#{format_decimal(value, 2)}%"
  end

  def format_market_cap(value)
    return '-' if value.nil?
    "#{format_decimal(value.to_f / 100_000_000.0, 1)}亿"
  end

  def format_volume(value)
    return '-' if value.nil?
    "#{format_decimal(value.to_f / 10_000.0, 2)}万手"
  end

  def format_shares(value)
    return '-' if value.nil?
    "#{format_decimal(value.to_f / 100_000_000.0, 2)}亿股"
  end

  def position_color(pos)
    return 'text-gray-400' if pos.nil?
    if pos < 0.2
      'text-green-600 font-bold'
    elsif pos < 0.4
      'text-green-500'
    elsif pos < 0.6
      'text-yellow-600'
    elsif pos < 0.8
      'text-red-500'
    else
      'text-red-700 font-bold'
    end
  end

  def sort_link(field, label)
    current = Array(@sorts)
    existing = current.find { |s| s[:field] == field }
    new_order = existing && existing[:order] == 'desc' ? 'asc' : 'desc'
    next_sorts = current.reject { |s| s[:field] == field }
    next_sorts.unshift({ field: field, order: new_order })

    icon = ''
    if existing
      idx = current.index(existing) + 1
      arrow = existing[:order] == 'desc' ? '↓' : '↑'
      icon = " #{idx}#{arrow}"
    end

    query_params = { sort: serialize_sorts_param(next_sorts) }
    query_params[:only_div5y] = '1' if params[:only_div5y].to_s == '1'
    include_ids = parse_id_list(params[:include_category_ids])
    exclude_ids = parse_id_list(params[:exclude_category_ids])
    query_params[:include_category_ids] = include_ids unless include_ids.empty?
    query_params[:exclude_category_ids] = exclude_ids unless exclude_ids.empty?
    include_pb = parse_id_list(params[:include_pb_levels]).select { |x| x >= 1 && x <= 6 }
    exclude_pb = parse_id_list(params[:exclude_pb_levels]).select { |x| x >= 1 && x <= 6 }
    query_params[:include_pb_levels] = include_pb unless include_pb.empty?
    query_params[:exclude_pb_levels] = exclude_pb unless exclude_pb.empty?
    include_pb_pct = parse_id_list(params[:include_pb_percentile_levels]).select { |x| x >= 1 && x <= 4 }
    exclude_pb_pct = parse_id_list(params[:exclude_pb_percentile_levels]).select { |x| x >= 1 && x <= 4 }
    query_params[:include_pb_percentile_levels] = include_pb_pct unless include_pb_pct.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_pct unless exclude_pb_pct.empty?

    "<a href='?#{build_query(query_params)}' class='hover:underline text-blue-600'>#{label}#{icon}</a>"
  end
end
