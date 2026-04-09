require 'sinatra'
require 'sinatra/reloader' if development?
require_relative 'models'

set :bind, '0.0.0.0'
set :port, 4567

get '/' do
  # 排序字段白名单
  allowed_sort_fields = %w[
    name code current_price expected_dividend_yield dividend_yield
    turnover_rate market_cap volume avg_price pe_ttm pb total_shares
    pos_30d pos_1y pos_3y pos_5y price_position
  ]
  
  sort_field = params[:sort] || 'expected_dividend_yield'
  sort_order = params[:order] || 'desc'
  category_id = params[:category_id]
  
  # 验证排序字段，防止 SQL 注入
  sort_field = 'expected_dividend_yield' unless allowed_sort_fields.include?(sort_field)
  sort_order = 'desc' unless %w[asc desc].include?(sort_order)
  
  @stocks = Stock.includes(:categories).order("#{sort_field} #{sort_order} NULLS LAST")
  
  if category_id && !category_id.to_s.empty?
    @stocks = @stocks.joins(:categorizations).where(categorizations: { category_id: category_id })
    @current_category = Category.find(category_id)
  end

  @categories = Category.joins(:categorizations).group('categories.id').order('count(categorizations.id) desc')
  @sort_field = sort_field
  @sort_order = sort_order
  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  
  erb :index
end

get '/macro' do
  @cn_10y_latest = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  @cn_10y_series = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :asc).pluck(:date, :yield_pct)
  erb :macro
end

get '/stocks/:id' do
  @stock = Stock.includes(:categories).find(params[:id])
  # 价格走势（取最近 10 年），按日期升序用于绘图
  @price_histories = @stock.price_histories.order(date: :asc)
  # 分红历史，按报告期降序展示
  @dividends = @stock.dividends.order(report_date: :desc)
  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  
  erb :show
end

helpers do
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
    new_order = (field == @sort_field && @sort_order == 'desc') ? 'asc' : 'desc'
    icon = if field == @sort_field
             @sort_order == 'desc' ? ' ↓' : ' ↑'
           else
             ''
           end
    
    query_params = { sort: field, order: new_order }
    query_params[:category_id] = params[:category_id] if params[:category_id] && !params[:category_id].to_s.empty?
    
    query_string = query_params.map { |k, v| "#{k}=#{v}" }.join('&')
    "<a href='?#{query_string}' class='hover:underline text-blue-600'>#{label}#{icon}</a>"
  end
end
