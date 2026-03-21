require 'sinatra'
require 'sinatra/reloader' if development?
require_relative 'models'

set :bind, '0.0.0.0'
set :port, 4567

get '/' do
  # 排序字段白名单
  allowed_sort_fields = %w[name code expected_dividend_yield dividend_yield current_price pos_30d pos_1y pos_3y pos_5y price_position]
  
  sort_field = params[:sort] || 'expected_dividend_yield'
  sort_order = params[:order] || 'desc'
  
  # 验证排序字段，防止 SQL 注入
  sort_field = 'expected_dividend_yield' unless allowed_sort_fields.include?(sort_field)
  sort_order = 'desc' unless %w[asc desc].include?(sort_order)
  
  @stocks = Stock.order("#{sort_field} #{sort_order} NULLS LAST")
  @sort_field = sort_field
  @sort_order = sort_order
  
  erb :index
end

get '/stocks/:id' do
  @stock = Stock.find(params[:id])
  # 价格走势（取最近 10 年），按日期升序用于绘图
  @price_histories = @stock.price_histories.order(date: :asc)
  # 分红历史，按报告期降序展示
  @dividends = @stock.dividends.order(report_date: :desc)
  
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
    "<a href='?sort=#{field}&order=#{new_order}' class='hover:underline text-blue-600'>#{label}#{icon}</a>"
  end
end
