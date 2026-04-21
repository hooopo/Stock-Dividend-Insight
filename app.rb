require 'date'
require 'securerandom'
require 'set'
require 'sinatra'
require 'sinatra/reloader' if development?
require_relative 'models'

unless defined?(RoeHistory)
  class RoeHistory < ActiveRecord::Base
    self.table_name = 'roe_histories'
    belongs_to :stock
  end
end

unless Stock.respond_to?(:reflect_on_association) && Stock.reflect_on_association(:roe_histories)
  Stock.has_many :roe_histories, dependent: :destroy
end

set :bind, '0.0.0.0'
set :port, 4567
enable :sessions
set :session_secret, ENV['SESSION_SECRET'] || SecureRandom.hex(64)

helpers do
  def current_user
    return nil unless session[:user_id]
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def logged_in?
    !current_user.nil?
  end

  def log_in(user)
    session[:user_id] = user.id
  end

  def log_out
    session.delete(:user_id)
    @current_user = nil
  end

  def flash
    session.delete(:flash)
  end

  def set_flash(message)
    session[:flash] = message.to_s
  end

  def redirect_back_or(default_path)
    to = session.delete(:return_to)
    redirect(to && to.to_s.size > 0 ? to : default_path)
  end

  def require_login!
    return if logged_in?
    session[:return_to] = request.fullpath
    set_flash('请先登录')
    redirect '/login'
  end

  def ensure_pool_tables!
    conn = ActiveRecord::Base.connection
    needed = %w[saved_pools pool_snapshots pool_snapshot_items]
    missing = needed.reject { |t| conn.data_source_exists?(t) }
    return if missing.empty?
    set_flash("股票池功能需要先跑数据库迁移：rake migrate（缺少表：#{missing.join(', ')}）")
    redirect '/'
  rescue StandardError => e
    set_flash("数据库未就绪：#{e.class}")
    redirect '/'
  end
end

get '/health' do
  'ok'
end

get '/signup' do
  if (rt = params[:return_to].to_s.strip).size > 0
    session[:return_to] = rt
  end
  erb :signup
end

post '/signup' do
  email = params[:email].to_s
  password = params[:password].to_s
  password_confirmation = params[:password_confirmation].to_s

  email = email.strip.downcase
  if email.empty?
    set_flash('邮箱不能为空')
    redirect '/signup'
  end

  if User.where(email: email).exists?
    set_flash('邮箱已存在')
    redirect '/signup'
  end

  user = User.new(email: email)
  user.password = password
  user.password_confirmation = password_confirmation

  if user.save
    log_in(user)
    redirect_back_or('/')
  else
    set_flash(user.errors.full_messages.join('；'))
    redirect '/signup'
  end
end

get '/login' do
  if (rt = params[:return_to].to_s.strip).size > 0
    session[:return_to] = rt
  end
  erb :login
end

post '/login' do
  email = params[:email].to_s.strip.downcase
  password = params[:password].to_s

  user = User.find_by(email: email)
  if user && user.authenticate(password)
    log_in(user)
    redirect_back_or('/')
  else
    set_flash('邮箱或密码不正确')
    redirect '/login'
  end
end

post '/logout' do
  log_out
  redirect '/login'
end

get '/pools' do
  require_login!
  ensure_pool_tables!
  @layout_full_width = true
  @pools = current_user.saved_pools.order(updated_at: :desc, id: :desc).to_a
  pool_ids = @pools.map(&:id)
  snapshots =
    pool_ids.empty? ? [] : PoolSnapshot.where(saved_pool_id: pool_ids).order(taken_at: :desc, id: :desc).to_a
  @latest_snapshot_by_pool_id = snapshots.group_by(&:saved_pool_id).transform_values { |arr| arr.first }
  @snapshot_count_by_pool_id = pool_ids.empty? ? {} : PoolSnapshot.where(saved_pool_id: pool_ids).group(:saved_pool_id).count
  erb :pools
end

post '/pools' do
  require_login!
  ensure_pool_tables!
  name = params[:name].to_s.strip
  query_string = params[:query].to_s.strip
  edit_pool_id = params[:edit_pool_id].to_s.strip

  if name.empty?
    set_flash('股票池名称不能为空')
    redirect_back_or('/')
  end

  if query_string.empty?
    set_flash('没有可保存的筛选条件')
    redirect_back_or('/')
  end

  if edit_pool_id.size > 0
    pool = current_user.saved_pools.find(edit_pool_id)
    if pool.pool_snapshots.exists?
      set_flash('已生成快照，股票池不可编辑')
      redirect "/pools/#{pool.id}"
    end
    pool.update!(name: name, query_string: normalized_pool_query_string(query_string))
    redirect "/pools/#{pool.id}"
  else
    pool = current_user.saved_pools.create!(name: name, query_string: normalized_pool_query_string(query_string))
    redirect "/pools/#{pool.id}"
  end
end

get '/pools/:id' do
  require_login!
  ensure_pool_tables!
  @layout_full_width = true
  @pool = current_user.saved_pools.find(params[:id])
  @snapshot = @pool.pool_snapshots.order(taken_at: :desc, id: :desc).first

  pool_params = parse_query_string_multi(@pool.query_string)
  @adv_filters = parse_advanced_filters(pool_params)
  @adv_fields = advanced_field_specs
  @only_div5y = pool_params['only_div5y'].to_s == '1'
  @roe_5y_avg_ge_12 = pool_params['roe_5y_avg_ge_12'].to_s == '1'
  @roe_5y_min_ge_8 = pool_params['roe_5y_min_ge_8'].to_s == '1'
  @exclude_high_debt = pool_params['exclude_high_debt'].to_s == '1'

  @include_category_ids = parse_id_list(pool_params['include_category_ids'])
  @exclude_category_ids = parse_id_list(pool_params['exclude_category_ids'])
  @include_pb_levels = parse_id_list(pool_params['include_pb_levels']).select { |x| x >= 1 && x <= 6 }
  @exclude_pb_levels = parse_id_list(pool_params['exclude_pb_levels']).select { |x| x >= 1 && x <= 6 }
  @include_pb_percentile_levels = parse_id_list(pool_params['include_pb_percentile_levels']).select { |x| x >= 1 && x <= 4 }
  @exclude_pb_percentile_levels = parse_id_list(pool_params['exclude_pb_percentile_levels']).select { |x| x >= 1 && x <= 4 }
  @include_pe_levels = parse_id_list(pool_params['include_pe_levels']).select { |x| x >= 1 && x <= 7 }
  @exclude_pe_levels = parse_id_list(pool_params['exclude_pe_levels']).select { |x| x >= 1 && x <= 7 }
  @include_pe_percentile_levels = parse_id_list(pool_params['include_pe_percentile_levels']).select { |x| x >= 1 && x <= 3 }
  @exclude_pe_percentile_levels = parse_id_list(pool_params['exclude_pe_percentile_levels']).select { |x| x >= 1 && x <= 3 }
  @include_peg_levels = parse_id_list(pool_params['include_peg_levels']).select { |x| x >= 1 && x <= 5 }
  @exclude_peg_levels = parse_id_list(pool_params['exclude_peg_levels']).select { |x| x >= 1 && x <= 5 }
  @include_roe_levels = parse_id_list(pool_params['include_roe_levels']).select { |x| x >= 1 && x <= 3 }
  @exclude_roe_levels = parse_id_list(pool_params['exclude_roe_levels']).select { |x| x >= 1 && x <= 3 }

  @included_categories = @include_category_ids.empty? ? [] : Category.where(id: @include_category_ids)
  @excluded_categories = @exclude_category_ids.empty? ? [] : Category.where(id: @exclude_category_ids)

  sorts = sorts_from_query_string(@pool.query_string)
  @sorts = sorts
  @sort_param = serialize_sorts_param(sorts)

  current_scope = stock_scope_from_query_string(@pool.query_string)
  @current_total_count = current_scope.count

  ordered_scope = order_scope_by_sorts(current_scope, sorts)

  page = params[:page].to_i
  page = 1 if page < 1
  per_page = 20
  @total_pages = (@current_total_count.to_f / per_page).ceil
  @total_pages = 1 if @total_pages < 1
  page = @total_pages if page > @total_pages
  @page = page
  @stocks = ordered_scope.offset((page - 1) * per_page).limit(per_page).to_a
  stock_ids = @stocks.map(&:id)
  @pe_hist_counts = stock_ids.empty? ? {} : PriceHistory.where(stock_id: stock_ids).where.not(pe_ttm: nil).group(:stock_id).count
  @pb_hist_counts = stock_ids.empty? ? {} : PriceHistory.where(stock_id: stock_ids).where.not(pb: nil).group(:stock_id).count
  if @snapshot
    base_items = @snapshot.pool_snapshot_items.where.not(code: nil).to_a
    @base_item_by_code = base_items.index_by(&:code)

    base_codes = @snapshot.pool_snapshot_items.where.not(code: nil).pluck(:code)
    current_codes = current_scope.where.not(code: nil).pluck(:code)

    base_set = base_codes.to_set
    current_set = current_codes.to_set
    @added_codes = (current_set - base_set).to_a
    @removed_codes = (base_set - current_set).to_a

    @added_stocks = @added_codes.empty? ? [] : Stock.where(code: @added_codes).order(:id).to_a
    @removed_items =
      @removed_codes.empty? ? [] : @snapshot.pool_snapshot_items.where(code: @removed_codes).order(:id).to_a
  else
    @base_item_by_code = {}
    @added_codes = []
    @removed_codes = []
    @added_stocks = []
    @removed_items = []
  end
  erb :pool_show
end

post '/pools/:id/snapshot' do
  require_login!
  ensure_pool_tables!
  pool = current_user.saved_pools.find(params[:id])
  if pool.pool_snapshots.exists?
    set_flash('已生成快照')
    redirect "/pools/#{pool.id}"
  end
  create_pool_snapshot!(pool)
  set_flash('已生成快照，股票池已锁定不可编辑')
  redirect "/pools/#{pool.id}"
end

post '/pools/:id/delete' do
  require_login!
  ensure_pool_tables!
  pool = current_user.saved_pools.find(params[:id])
  pool.destroy!
  set_flash('已删除股票池')
  redirect '/pools'
end

get '/' do
  @layout_full_width = true
  allowed_sort_fields = %w[
    current_price dividend_yield
    turnover_rate volume pe_ttm pe_level pe_percentile pb pb_level pb_percentile roe_jq roe_level total_shares
    peg peg_level net_profit_yoy asset_liability_ratio interest_debt_ratio fcf_yield fcf_ev
    drop_30d pos_30d pos_1y pos_3y pos_5y price_position
  ]
  
  adv_filters = parse_advanced_filters(params)

  only_div5y = params[:only_div5y].to_s == '1'
  include_category_ids = parse_id_list(params[:include_category_ids])
  exclude_category_ids = parse_id_list(params[:exclude_category_ids])
  include_pb_levels = parse_id_list(params[:include_pb_levels]).select { |x| x >= 1 && x <= 6 }
  exclude_pb_levels = parse_id_list(params[:exclude_pb_levels]).select { |x| x >= 1 && x <= 6 }
  include_pb_percentile_levels = parse_id_list(params[:include_pb_percentile_levels]).select { |x| x >= 1 && x <= 4 }
  exclude_pb_percentile_levels = parse_id_list(params[:exclude_pb_percentile_levels]).select { |x| x >= 1 && x <= 4 }
  include_pe_levels = parse_id_list(params[:include_pe_levels]).select { |x| x >= 1 && x <= 7 }
  exclude_pe_levels = parse_id_list(params[:exclude_pe_levels]).select { |x| x >= 1 && x <= 7 }
  include_pe_percentile_levels = parse_id_list(params[:include_pe_percentile_levels]).select { |x| x >= 1 && x <= 3 }
  exclude_pe_percentile_levels = parse_id_list(params[:exclude_pe_percentile_levels]).select { |x| x >= 1 && x <= 3 }
  include_peg_levels = parse_id_list(params[:include_peg_levels]).select { |x| x >= 1 && x <= 5 }
  exclude_peg_levels = parse_id_list(params[:exclude_peg_levels]).select { |x| x >= 1 && x <= 5 }
  exclude_high_debt = params[:exclude_high_debt].to_s == '1'
  roe_5y_avg_ge_12 = params[:roe_5y_avg_ge_12].to_s == '1'
  roe_5y_min_ge_8 = params[:roe_5y_min_ge_8].to_s == '1'
  roe_min = nil
  roe_max = nil
  include_roe_levels = parse_id_list(params[:include_roe_levels]).select { |x| x >= 1 && x <= 3 }
  exclude_roe_levels = parse_id_list(params[:exclude_roe_levels]).select { |x| x >= 1 && x <= 3 }

  sorts = parse_sorts_param(params[:sort], allowed_sort_fields)

  build_index_query_params = lambda do
    query_params = { sort: serialize_sorts_param(sorts) }
    if adv_filters.any?
      query_params[:adv_field] = adv_filters.map { |x| x[:field] }
      query_params[:adv_op] = adv_filters.map { |x| x[:op] }
      query_params[:adv_value] = adv_filters.map { |x| x[:raw_value] }
    end
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:roe_5y_avg_ge_12] = '1' if roe_5y_avg_ge_12
    query_params[:roe_5y_min_ge_8] = '1' if roe_5y_min_ge_8
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_pb_levels] = include_pb_levels unless include_pb_levels.empty?
    query_params[:exclude_pb_levels] = exclude_pb_levels unless exclude_pb_levels.empty?
    query_params[:include_pb_percentile_levels] = include_pb_percentile_levels unless include_pb_percentile_levels.empty?
    query_params[:exclude_pb_percentile_levels] = exclude_pb_percentile_levels unless exclude_pb_percentile_levels.empty?
    query_params[:include_pe_levels] = include_pe_levels unless include_pe_levels.empty?
    query_params[:exclude_pe_levels] = exclude_pe_levels unless exclude_pe_levels.empty?
    query_params[:include_pe_percentile_levels] = include_pe_percentile_levels unless include_pe_percentile_levels.empty?
    query_params[:exclude_pe_percentile_levels] = exclude_pe_percentile_levels unless exclude_pe_percentile_levels.empty?
    query_params[:include_peg_levels] = include_peg_levels unless include_peg_levels.empty?
    query_params[:exclude_peg_levels] = exclude_peg_levels unless exclude_peg_levels.empty?
    query_params[:exclude_high_debt] = '1' if exclude_high_debt
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    query_params
  end

  if (move_field = params[:move_sort].to_s.strip).size > 0
    dir = params[:move_dir].to_s
    idx = sorts.index { |s| s[:field] == move_field }
    if idx
      if dir == 'up' && idx > 0
        sorts[idx - 1], sorts[idx] = sorts[idx], sorts[idx - 1]
      elsif dir == 'down' && idx < sorts.size - 1
        sorts[idx + 1], sorts[idx] = sorts[idx], sorts[idx + 1]
      end
    end

    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (add_field = params[:add_sort_field].to_s.strip).size > 0
    if allowed_sort_fields.include?(add_field)
      add_order = params[:add_sort_order].to_s.downcase
      add_order = 'desc' unless %w[asc desc].include?(add_order)
      add_pos = params[:add_sort_pos].to_s

      sorts = sorts.reject { |s| s[:field] == add_field }
      entry = { field: add_field, order: add_order }
      if add_pos == 'primary'
        sorts.unshift(entry)
      else
        sorts.push(entry)
      end
      sorts = default_sorts if sorts.empty?
    end

    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_include = params[:remove_include_category_id].to_s.strip).size > 0
    include_category_ids = include_category_ids.reject { |x| x == remove_include.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_exclude = params[:remove_exclude_category_id].to_s.strip).size > 0
    exclude_category_ids = exclude_category_ids.reject { |x| x == remove_exclude.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_include = params[:remove_include_pb_level].to_s.strip).size > 0
    include_pb_levels = include_pb_levels.reject { |x| x == remove_include.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_exclude = params[:remove_exclude_pb_level].to_s.strip).size > 0
    exclude_pb_levels = exclude_pb_levels.reject { |x| x == remove_exclude.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_include = params[:remove_include_pb_percentile_level].to_s.strip).size > 0
    include_pb_percentile_levels = include_pb_percentile_levels.reject { |x| x == remove_include.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_exclude = params[:remove_exclude_pb_percentile_level].to_s.strip).size > 0
    exclude_pb_percentile_levels = exclude_pb_percentile_levels.reject { |x| x == remove_exclude.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_include = params[:remove_include_peg_level].to_s.strip).size > 0
    include_peg_levels = include_peg_levels.reject { |x| x == remove_include.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_exclude = params[:remove_exclude_peg_level].to_s.strip).size > 0
    exclude_peg_levels = exclude_peg_levels.reject { |x| x == remove_exclude.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_include = params[:remove_include_pe_level].to_s.strip).size > 0
    include_pe_levels = include_pe_levels.reject { |x| x == remove_include.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_exclude = params[:remove_exclude_pe_level].to_s.strip).size > 0
    exclude_pe_levels = exclude_pe_levels.reject { |x| x == remove_exclude.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_include = params[:remove_include_pe_percentile_level].to_s.strip).size > 0
    include_pe_percentile_levels = include_pe_percentile_levels.reject { |x| x == remove_include.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_exclude = params[:remove_exclude_pe_percentile_level].to_s.strip).size > 0
    exclude_pe_percentile_levels = exclude_pe_percentile_levels.reject { |x| x == remove_exclude.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end

  if (remove_sort = params[:remove_sort].to_s.strip).size > 0
    sorts = sorts.reject { |s| s[:field] == remove_sort }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end
  if (remove_include = params[:remove_include_roe_level].to_s.strip).size > 0
    include_roe_levels = include_roe_levels.reject { |x| x == remove_include.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end
  if (remove_exclude = params[:remove_exclude_roe_level].to_s.strip).size > 0
    exclude_roe_levels = exclude_roe_levels.reject { |x| x == remove_exclude.to_i }
    redirect "/?#{Rack::Utils.build_query(build_index_query_params.call)}"
  end
  if params[:clear_sorts].to_s == '1'
    redirect '/'
  end

  base_scope = build_filtered_scope(params)

  order_sql = sorts.map { |s| "#{s[:field]} #{s[:order]} NULLS LAST" }.join(', ')
  page = params[:page].to_i
  page = 1 if page < 1
  per_page = 20

  @total_count = base_scope.count
  @total_pages = (@total_count.to_f / per_page).ceil
  @total_pages = 1 if @total_pages < 1
  page = @total_pages if page > @total_pages
  @page = page

  ordered_scope = sorts.empty? ? base_scope.order(id: :desc) : base_scope.order(order_sql)
  @stocks = ordered_scope.offset((page - 1) * per_page).limit(per_page)
  stock_ids = @stocks.map(&:id)
  @pe_hist_counts = PriceHistory.where(stock_id: stock_ids).where.not(pe_ttm: nil).group(:stock_id).count
  @pb_hist_counts = PriceHistory.where(stock_id: stock_ids).where.not(pb: nil).group(:stock_id).count

  @categories = Category.joins(:categorizations).group('categories.id').order('count(categorizations.id) desc')
  @include_category_ids = include_category_ids
  @exclude_category_ids = exclude_category_ids
  @included_categories = include_category_ids.empty? ? [] : Category.where(id: include_category_ids)
  @excluded_categories = exclude_category_ids.empty? ? [] : Category.where(id: exclude_category_ids)
  @include_pb_levels = include_pb_levels
  @exclude_pb_levels = exclude_pb_levels
  @include_pb_percentile_levels = include_pb_percentile_levels
  @exclude_pb_percentile_levels = exclude_pb_percentile_levels
  @include_pe_levels = include_pe_levels
  @exclude_pe_levels = exclude_pe_levels
  @include_pe_percentile_levels = include_pe_percentile_levels
  @exclude_pe_percentile_levels = exclude_pe_percentile_levels
  @include_peg_levels = include_peg_levels
  @exclude_peg_levels = exclude_peg_levels
  @exclude_high_debt = exclude_high_debt
  @include_roe_levels = include_roe_levels
  @exclude_roe_levels = exclude_roe_levels
  @allowed_sort_fields = allowed_sort_fields
  @sorts = sorts
  @sort_param = serialize_sorts_param(sorts)
  @adv_filters = adv_filters
  @adv_fields = advanced_field_specs
  @only_div5y = only_div5y
  @roe_5y_avg_ge_12 = roe_5y_avg_ge_12
  @roe_5y_min_ge_8 = roe_5y_min_ge_8
  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  @edit_pool_id = nil
  @edit_pool_name = nil
  if logged_in?
    edit_pool_id = params[:edit_pool_id].to_s.strip
    if edit_pool_id.size > 0
      pool = current_user.saved_pools.find_by(id: edit_pool_id)
      if pool && !pool.pool_snapshots.exists?
        @edit_pool_id = pool.id
        @edit_pool_name = pool.name.to_s
      end
    end
  end
  
  erb :index
end

get '/macro' do
  @cn_10y_latest = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  @cn_10y_series = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :asc).pluck(:date, :yield_pct)

  @hs300_eval = QiemanIndexEval.where(index_code: '000300.SH').order(eval_date: :desc).first
  @a500_eval = QiemanIndexEval.where(index_code: '000510.SH').order(eval_date: :desc).first

  erb :macro
end

get '/etfs' do
  @layout_full_width = true
  @sort = params[:sort].to_s.strip
  @dir = params[:dir].to_s.strip.downcase
  @sort = 'pb_percentile' if @sort.empty?
  @dir = %w[asc desc].include?(@dir) ? @dir : 'asc'

  @index_evals =
    QiemanIndexEval
      .select('DISTINCT ON (index_code) *')
      .order('index_code, eval_date DESC')
      .to_a
      .select { |x| Array(x.fund_codes).any? }

  allowed = %w[index_code index_name pe pe_percentile pb pb_percentile roe eval_date]
  @sort = 'pb_percentile' unless allowed.include?(@sort)
  field = @sort
  dir = @dir
  @index_evals =
    @index_evals.sort do |a, b|
      av = a.public_send(field)
      bv = b.public_send(field)

      if av.nil? && bv.nil?
        a.index_code.to_s <=> b.index_code.to_s
      elsif av.nil?
        1
      elsif bv.nil?
        -1
      else
        if av.is_a?(String) || bv.is_a?(String) || field.end_with?('_code') || field.end_with?('_name')
          av.to_s <=> bv.to_s
        else
          av.to_f <=> bv.to_f
        end
      end
    end
  @index_evals.reverse! if dir == 'desc'

  erb :etfs
end

get '/indices' do
  @layout_full_width = true
  @sort = params[:sort].to_s.strip
  @dir = params[:dir].to_s.strip.downcase
  @sort = 'pb_percentile' if @sort.empty?
  @dir = %w[asc desc].include?(@dir) ? @dir : 'asc'

  @indices =
    QiemanIndexEval
      .select('DISTINCT ON (index_code) *')
      .order('index_code, eval_date DESC')
      .to_a

  allowed = %w[index_code index_name pe pe_percentile pb pb_percentile roe eval_date]
  @sort = 'pb_percentile' unless allowed.include?(@sort)
  field = @sort
  dir = @dir
  @indices =
    @indices.sort do |a, b|
      av = a.public_send(field)
      bv = b.public_send(field)

      if av.nil? && bv.nil?
        a.index_code.to_s <=> b.index_code.to_s
      elsif av.nil?
        1
      elsif bv.nil?
        -1
      else
        if av.is_a?(String) || bv.is_a?(String) || field.end_with?('_code') || field.end_with?('_name')
          av.to_s <=> bv.to_s
        else
          av.to_f <=> bv.to_f
        end
      end
    end
  @indices.reverse! if dir == 'desc'

  erb :indices
end

get '/kb' do
  erb :kb_index
end

get '/kb/pb' do
  erb :kb_pb
end

get '/kb/pe' do
  erb :kb_pe
end

get '/kb/peg' do
  erb :kb_peg
end

get '/kb/index_eval' do
  erb :kb_index_eval
end

get '/kb/debt' do
  erb :kb_debt
end

get '/kb/cycle' do
  erb :kb_cycle_volatility
end

get '/kb/roe' do
  erb :kb_roe
end

get '/kb/dividend' do
  erb :kb_dividend
end

get '/kb/fcf' do
  erb :kb_fcf
end

get '/stocks/:id' do
  @stock = Stock.includes(:categories).find(params[:id])
  from_date = Date.today << 120
  # 价格走势（取最近 10 年），按日期升序用于绘图
  @price_histories = @stock.price_histories.where('date >= ?', from_date).order(date: :asc)
  ph_arr = @price_histories.to_a
  if ph_arr.size > 700
    stride = (ph_arr.size / 700.0).ceil
    sampled = ph_arr.each_with_index.filter_map { |row, idx| idx % stride == 0 ? row : nil }
    sampled << ph_arr.last if sampled.last != ph_arr.last
    @price_histories = sampled
  end
  # 分红历史，按报告期降序展示
  @dividends = @stock.dividends.order(report_date: :desc)
  @roe_annual_rows =
    @stock
      .roe_histories
      .where(report_type: '年报')
      .where.not(roe_jq: nil)
      .order(report_date: :asc)

  roe_last5 = @roe_annual_rows.last(5)
  roe_vals = roe_last5.map { |r| r.roe_jq }.compact.map(&:to_f)
  if roe_last5.size == 5 && roe_vals.size == 5
    @roe_5y_avg = roe_vals.sum / roe_vals.size.to_f
    @roe_5y_min = roe_vals.min
  else
    @roe_5y_avg = nil
    @roe_5y_min = nil
  end

  annual_div_cash = Hash.new(0.0)
  @dividends.each do |div|
    y = div.report_date&.year
    next unless y
    annual_div_cash[y] += div.cash_dividend.to_f if div.cash_dividend
  end
  @annual_dividends =
    annual_div_cash
      .sort_by { |y, _| -y }
      .take(10)
      .reverse
      .map { |y, cash| { year: y, cash: cash } }

  @cn_10y = TreasuryYield.where(country: 'CN', tenor: '10Y').order(date: :desc).first
  
  erb :show
end

helpers do
  def allowed_sort_fields_for_list
    %w[
      current_price dividend_yield
      turnover_rate volume pe_ttm pe_level pe_percentile pb pb_level pb_percentile roe_jq roe_level total_shares
      peg peg_level net_profit_yoy asset_liability_ratio interest_debt_ratio fcf_yield fcf_ev
      drop_30d pos_30d pos_1y pos_3y pos_5y price_position
    ]
  end

  def param_value(params_hash, key)
    params_hash[key] || params_hash[key.to_s]
  end

  def build_filtered_scope(params_hash)
    adv_filters = parse_advanced_filters(params_hash)
    only_div5y = param_value(params_hash, :only_div5y).to_s == '1'
    roe_5y_avg_ge_12 = param_value(params_hash, :roe_5y_avg_ge_12).to_s == '1'
    roe_5y_min_ge_8 = param_value(params_hash, :roe_5y_min_ge_8).to_s == '1'
    exclude_high_debt = param_value(params_hash, :exclude_high_debt).to_s == '1'

    include_category_ids = parse_id_list(param_value(params_hash, :include_category_ids))
    exclude_category_ids = parse_id_list(param_value(params_hash, :exclude_category_ids))
    include_pb_levels = parse_id_list(param_value(params_hash, :include_pb_levels)).select { |x| x >= 1 && x <= 6 }
    exclude_pb_levels = parse_id_list(param_value(params_hash, :exclude_pb_levels)).select { |x| x >= 1 && x <= 6 }
    include_pb_percentile_levels = parse_id_list(param_value(params_hash, :include_pb_percentile_levels)).select { |x| x >= 1 && x <= 4 }
    exclude_pb_percentile_levels = parse_id_list(param_value(params_hash, :exclude_pb_percentile_levels)).select { |x| x >= 1 && x <= 4 }
    include_pe_levels = parse_id_list(param_value(params_hash, :include_pe_levels)).select { |x| x >= 1 && x <= 7 }
    exclude_pe_levels = parse_id_list(param_value(params_hash, :exclude_pe_levels)).select { |x| x >= 1 && x <= 7 }
    include_pe_percentile_levels = parse_id_list(param_value(params_hash, :include_pe_percentile_levels)).select { |x| x >= 1 && x <= 3 }
    exclude_pe_percentile_levels = parse_id_list(param_value(params_hash, :exclude_pe_percentile_levels)).select { |x| x >= 1 && x <= 3 }
    include_peg_levels = parse_id_list(param_value(params_hash, :include_peg_levels)).select { |x| x >= 1 && x <= 5 }
    exclude_peg_levels = parse_id_list(param_value(params_hash, :exclude_peg_levels)).select { |x| x >= 1 && x <= 5 }
    include_roe_levels = parse_id_list(param_value(params_hash, :include_roe_levels)).select { |x| x >= 1 && x <= 3 }
    exclude_roe_levels = parse_id_list(param_value(params_hash, :exclude_roe_levels)).select { |x| x >= 1 && x <= 3 }

    sorts = parse_sorts_param(param_value(params_hash, :sort), allowed_sort_fields_for_list)

    scope = Stock.where(asset_type: 'stock').includes(:categories)
    scope = scope.where(has_dividend_5y: true) if only_div5y
    scope = scope.where(roe_5y_avg_ge_12: true) if roe_5y_avg_ge_12
    scope = scope.where(roe_5y_min_ge_8: true) if roe_5y_min_ge_8
    scope = scope.where(roe_level: include_roe_levels) if include_roe_levels.any?
    scope = scope.where.not(roe_level: exclude_roe_levels) if exclude_roe_levels.any?
    if include_category_ids.any?
      scope = scope.joins(:categorizations).where(categorizations: { category_id: include_category_ids }).distinct
    end
    if exclude_category_ids.any?
      excluded = Stock.joins(:categorizations).where(categorizations: { category_id: exclude_category_ids }).select(:id)
      scope = scope.where.not(id: excluded)
    end
    scope = scope.where(pb_level: include_pb_levels) if include_pb_levels.any?
    scope = scope.where.not(pb_level: exclude_pb_levels) if exclude_pb_levels.any?
    scope = scope.where(pb_percentile_level: include_pb_percentile_levels) if include_pb_percentile_levels.any?
    scope = scope.where.not(pb_percentile_level: exclude_pb_percentile_levels) if exclude_pb_percentile_levels.any?
    scope = scope.where(peg_level: include_peg_levels) if include_peg_levels.any?
    scope = scope.where.not(peg_level: exclude_peg_levels) if exclude_peg_levels.any?
    scope = scope.where(pe_level: include_pe_levels) if include_pe_levels.any?
    scope = scope.where.not(pe_level: exclude_pe_levels) if exclude_pe_levels.any?
    scope = scope.where(pe_percentile_level: include_pe_percentile_levels) if include_pe_percentile_levels.any?
    scope = scope.where.not(pe_percentile_level: exclude_pe_percentile_levels) if exclude_pe_percentile_levels.any?
    scope = scope.where('asset_liability_ratio <= 60 OR asset_liability_ratio IS NULL') if exclude_high_debt
    sorts.each do |s|
      scope = scope.where('pe_ttm > 0') if s[:field] == 'pe_ttm' && s[:order] == 'asc'
    end

    apply_advanced_filters(scope, adv_filters)
  end

  def sorts_from_query_string(query_string)
    p = parse_query_string_multi(query_string)
    parse_sorts_param(p['sort'], allowed_sort_fields_for_list)
  end

  def order_scope_by_sorts(scope, sorts)
    s = Array(sorts)
    return scope.order(id: :desc) if s.empty?
    order_sql = s.map { |x| "#{x[:field]} #{x[:order]} NULLS LAST" }.join(', ')
    scope.order(order_sql)
  end

  def format_signed(value, precision = 2, suffix = '')
    return nil if value.nil?
    v = value.to_f
    return nil if v.abs < 1e-9
    sign = v > 0 ? '+' : ''
    "#{sign}#{format_decimal(v, precision)}#{suffix}"
  end

  def format_signed_pp(value, precision = 2)
    format_signed(value, precision, 'pp')
  end

  def format_signed_ratio_delta(value, precision = 0)
    return nil if value.nil?
    format_signed(value.to_f * 100.0, precision, '%')
  end

  def delta_text_class(value)
    return 'text-gray-500' if value.nil?
    v = value.to_f
    return 'text-gray-500' if v.abs < 1e-9
    v > 0 ? 'text-red-600' : 'text-gray-500'
  end

  def normalized_pool_query_string(query_string)
    h = parse_query_string_multi(query_string)
    %w[
      page move_sort move_dir add_sort_field add_sort_order add_sort_pos clear_sorts
      remove_include_category_id remove_exclude_category_id
      remove_include_pb_level remove_exclude_pb_level
      remove_include_pb_percentile_level remove_exclude_pb_percentile_level
      remove_include_pe_level remove_exclude_pe_level
      remove_include_pe_percentile_level remove_exclude_pe_percentile_level
      remove_include_peg_level remove_exclude_peg_level
      remove_include_roe_level remove_exclude_roe_level
    ].each { |k| h.delete(k) }

    build_query(h)
  end

  def stock_scope_from_query_string(query_string)
    p = parse_query_string_multi(query_string)
    build_filtered_scope(p)
  end

  def create_pool_snapshot!(pool)
    scope = stock_scope_from_query_string(pool.query_string)
    taken_at = Time.now
    snapshot = pool.pool_snapshots.create!(taken_at: taken_at, total_count: scope.count)

    cols = %i[
      id code name current_price dividend_yield expected_dividend_yield pe_ttm pb peg roe_jq
      asset_liability_ratio interest_debt_ratio fcf_yield fcf_ev pe_percentile pb_percentile
      price_position pos_30d drop_30d market_cap turnover_rate volume
    ]

    scope.in_batches(of: 500) do |rel|
      rows =
        rel.pluck(*cols).map do |r|
          id, code, name, current_price, dividend_yield, expected_dividend_yield, pe_ttm, pb, peg, roe_jq,
            asset_liability_ratio, interest_debt_ratio, fcf_yield, fcf_ev, pe_percentile, pb_percentile,
            price_position, pos_30d, drop_30d, market_cap, turnover_rate, volume = r

          {
            pool_snapshot_id: snapshot.id,
            stock_id: id,
            code: code,
            name: name,
            current_price: current_price,
            dividend_yield: dividend_yield,
            expected_dividend_yield: expected_dividend_yield,
            pe_ttm: pe_ttm,
            pb: pb,
            peg: peg,
            roe_jq: roe_jq,
            asset_liability_ratio: asset_liability_ratio,
            interest_debt_ratio: interest_debt_ratio,
            fcf_yield: fcf_yield,
            fcf_ev: fcf_ev,
            pe_percentile: pe_percentile,
            pb_percentile: pb_percentile,
            price_position: price_position,
            pos_30d: pos_30d,
            drop_30d: drop_30d,
            market_cap: market_cap,
            turnover_rate: turnover_rate,
            volume: volume,
            created_at: taken_at,
            updated_at: taken_at
          }
        end

      PoolSnapshotItem.insert_all(rows) if rows.any?
    end

    snapshot
  end

  def delta(base, cur)
    return nil if base.nil? || cur.nil?
    cur.to_f - base.to_f
  end

  def pct_change(base, cur)
    return nil if base.nil? || cur.nil?
    b = base.to_f
    return nil if b == 0.0
    (cur.to_f - b) / b * 100.0
  end

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

  def parse_sorts_param(raw, allowed_fields)
    tokens = raw.to_s.split(',').map(&:strip).reject(&:empty?)
    return [] if tokens.empty?

    out = []
    tokens.each do |tok|
      field, order = tok.split(':', 2)
      next unless allowed_fields.include?(field)
      order = order.to_s.downcase
      order = 'desc' unless %w[asc desc].include?(order)
      next if out.any? { |x| x[:field] == field }
      out << { field: field, order: order }
    end

    out
  end

  def serialize_sorts_param(sorts)
    Array(sorts).map { |s| "#{s[:field]}:#{s[:order]}" }.join(',')
  end

  def build_query(params_hash)
    cleaned =
      params_hash.reject do |_, v|
        v.nil? || (v.respond_to?(:empty?) && v.empty?) || v.to_s.empty?
      end
    Rack::Utils.build_nested_query(cleaned)
  end

  def parse_query_string_multi(query_string)
    qs = query_string.to_s
    return {} if qs.empty?

    out = {}
    qs.split('&').each do |part|
      next if part.to_s.empty?
      k, v = part.split('=', 2)
      key = Rack::Utils.unescape(k.to_s)
      val = Rack::Utils.unescape(v.to_s)
      next if key.empty?

      if key.end_with?('[]')
        base = key[0..-3]
        (out[base] ||= []) << val
      elsif out.key?(key)
        out[key] = Array(out[key]) << val
      else
        out[key] = val
      end
    end

    out
  end

  def advanced_field_specs
    [
      { field: 'fcf_ev', label: 'FCF/EV', type: 'pct', placeholder: '3 或 3%' },
      { field: 'fcf_yield', label: 'FCF收益率', type: 'pct', placeholder: '3 或 3%' },
      { field: 'peg', label: 'PEG', type: 'number', placeholder: '0.8' },
      { field: 'pe_ttm', label: 'PE(TTM)', type: 'number', placeholder: '10' },
      { field: 'pb', label: 'PB', type: 'number', placeholder: '1.2' },
      { field: 'pe_percentile', label: 'PE分位', type: 'ratio', placeholder: '30% 或 0.3' },
      { field: 'pb_percentile', label: 'PB分位', type: 'ratio', placeholder: '30% 或 0.3' },
      { field: 'roe_jq', label: 'ROE(加权)', type: 'pct', placeholder: '10 或 10%' },
      { field: 'net_profit_yoy', label: '净利同比', type: 'pct', placeholder: '5 或 5%' },
      { field: 'asset_liability_ratio', label: '资产负债率', type: 'pct', placeholder: '60 或 60%' },
      { field: 'interest_debt_ratio', label: '有息负债率', type: 'pct', placeholder: '20 或 20%' },
      { field: 'dividend_yield', label: '历史股息率', type: 'pct', placeholder: '5 或 5%' },
      { field: 'expected_dividend_yield', label: '预期股息率', type: 'pct', placeholder: '5 或 5%' },
      { field: 'drop_30d', label: '30日跌幅', type: 'pct', placeholder: '10 或 10%' },
      { field: 'pos_30d', label: '30d分位', type: 'ratio', placeholder: '20% 或 0.2' },
      { field: 'pos_1y', label: '1y分位', type: 'ratio', placeholder: '20% 或 0.2' },
      { field: 'pos_3y', label: '3y分位', type: 'ratio', placeholder: '20% 或 0.2' },
      { field: 'pos_5y', label: '5y分位', type: 'ratio', placeholder: '20% 或 0.2' },
      { field: 'price_position', label: '全量分位', type: 'ratio', placeholder: '20% 或 0.2' }
    ]
  end

  def advanced_field_spec_by_name(field)
    advanced_field_specs.find { |x| x[:field] == field.to_s }
  end

  def parse_advanced_filters(params_hash)
    fields = Array(params_hash[:adv_field] || params_hash['adv_field'])
    ops = Array(params_hash[:adv_op] || params_hash['adv_op'])
    values = Array(params_hash[:adv_value] || params_hash['adv_value'])

    n = [fields.size, ops.size, values.size].max
    return [] if n == 0

    out = []
    n.times do |i|
      field = fields[i].to_s.strip
      op = ops[i].to_s.strip
      raw_value = values[i]
      raw_value = raw_value.nil? ? '' : raw_value.to_s.strip

      next if field.empty? || op.empty?
      spec = advanced_field_spec_by_name(field)
      next unless spec

      if %w[is_null not_null].include?(op)
        out << { field: field, op: op, raw_value: '' }
        next
      end

      next if raw_value.empty?
      out << { field: field, op: op, raw_value: raw_value }
    end

    out
  end

  def apply_advanced_filters(scope, adv_filters)
    return scope if adv_filters.nil? || adv_filters.empty?
    table = Stock.arel_table

    adv_filters.each do |f|
      field = f[:field].to_s
      op = f[:op].to_s
      spec = advanced_field_spec_by_name(field)
      next unless spec

      col = table[field]
      if op == 'is_null'
        scope = scope.where(col.eq(nil))
        next
      end
      if op == 'not_null'
        scope = scope.where(col.not_eq(nil))
        next
      end

      v = parse_advanced_value(spec[:type], f[:raw_value])
      next if v.nil?

      predicate =
        case op
        when '>'
          col.gt(v)
        when '>='
          col.gteq(v)
        when '<'
          col.lt(v)
        when '<='
          col.lteq(v)
        when '=', '=='
          col.eq(v)
        when '!=', '<>'
          col.not_eq(v)
        else
          nil
        end

      scope = predicate ? scope.where(predicate) : scope
    end

    scope
  end

  def parse_advanced_value(type, raw)
    s = raw.to_s.strip
    return nil if s.empty?

    if type.to_s == 'ratio'
      if s.end_with?('%')
        return s.sub(/%\z/, '').to_f / 100.0
      end
      return s.to_f if s.match?(/\A-?\d+(\.\d+)?\z/)
      nil
    elsif type.to_s == 'pct'
      if s.end_with?('%')
        return s.sub(/%\z/, '').to_f
      end
      return s.to_f if s.match?(/\A-?\d+(\.\d+)?\z/)
      nil
    elsif type.to_s == 'number'
      return s.to_f if s.match?(/\A-?\d+(\.\d+)?\z/)
      nil
    else
      return s.to_f if s.match?(/\A-?\d+(\.\d+)?\z/)
      nil
    end
  end

  def sort_label(field)
    {
      'name' => '股票名称',
      'code' => '代码',
      'current_price' => '最新价',
      'dividend_yield' => '历史股息率',
      'turnover_rate' => '换手率',
      'volume' => '成交量',
      'pe_ttm' => 'PE(TTM)',
      'peg' => 'PEG',
      'peg_level' => 'PEG等级',
      'net_profit_yoy' => '净利同比',
      'asset_liability_ratio' => '资产负债率',
      'interest_debt_ratio' => '有息负债率',
      'fcf_yield' => 'FCF收益率',
      'fcf_ev' => 'FCF/EV',
      'pe_level' => 'PE等级',
      'pe_percentile' => 'PE历史分位',
      'pb' => 'PB',
      'pb_level' => 'PB等级',
      'pb_percentile' => 'PB历史分位',
      'roe_jq' => 'ROE(加权)',
      'roe_level' => 'ROE等级',
      'total_shares' => '总股本',
      'pos_30d' => '30d分位',
      'drop_30d' => '30日跌幅',
      'pos_1y' => '1y分位',
      'pos_3y' => '3y分位',
      'pos_5y' => '5y分位',
      'price_position' => '全量分位'
    }[field] || field
  end

  def roe_level_label(level)
    case level.to_i
    when 1 then '一般'
    when 2 then '优秀'
    when 3 then '非常优秀'
    else
      '-'
    end
  end

  def roe_level_badge_class(level)
    case level.to_i
    when 1 then 'bg-gray-50 text-gray-700 border-gray-200'
    when 2 then 'bg-green-50 text-green-700 border-green-200'
    when 3 then 'bg-green-100 text-green-900 border-green-200'
    else
      'bg-gray-50 text-gray-500 border-gray-200'
    end
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

  def pb_level_class(level)
    case level.to_i
    when 1 then 'text-green-700 font-semibold'
    when 2 then 'text-green-600 font-semibold'
    when 3 then 'text-yellow-600 font-semibold'
    when 4 then 'text-orange-600 font-semibold'
    when 5 then 'text-red-600 font-semibold'
    when 6 then 'text-red-700 font-semibold'
    else
      'text-gray-400'
    end
  end

  def pb_level_badge_class(level)
    case level.to_i
    when 1 then 'bg-green-100 text-green-800 border-green-200'
    when 2 then 'bg-green-50 text-green-700 border-green-200'
    when 3 then 'bg-yellow-50 text-yellow-800 border-yellow-200'
    when 4 then 'bg-orange-50 text-orange-800 border-orange-200'
    when 5 then 'bg-red-50 text-red-800 border-red-200'
    when 6 then 'bg-red-100 text-red-900 border-red-200'
    else
      'bg-gray-50 text-gray-500 border-gray-200'
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

  def pe_level_label(level)
    case level.to_i
    when 1 then '亏损'
    when 2 then '极低估'
    when 3 then '低估'
    when 4 then '合理'
    when 5 then '偏高'
    when 6 then '高估'
    when 7 then '极高估'
    else
      '-'
    end
  end

  def pe_level_class(level)
    case level.to_i
    when 1 then 'text-gray-600 font-semibold'
    when 2 then 'text-green-700 font-semibold'
    when 3 then 'text-green-600 font-semibold'
    when 4 then 'text-yellow-600 font-semibold'
    when 5 then 'text-orange-600 font-semibold'
    when 6 then 'text-red-600 font-semibold'
    when 7 then 'text-red-700 font-semibold'
    else
      'text-gray-400'
    end
  end

  def pe_level_badge_class(level)
    case level.to_i
    when 1 then 'bg-gray-100 text-gray-800 border-gray-200'
    when 2 then 'bg-green-100 text-green-800 border-green-200'
    when 3 then 'bg-green-50 text-green-700 border-green-200'
    when 4 then 'bg-yellow-50 text-yellow-800 border-yellow-200'
    when 5 then 'bg-orange-50 text-orange-800 border-orange-200'
    when 6 then 'bg-red-50 text-red-800 border-red-200'
    when 7 then 'bg-red-100 text-red-900 border-red-200'
    else
      'bg-gray-50 text-gray-500 border-gray-200'
    end
  end

  def peg_level_label(level)
    case level.to_i
    when 1 then '极低估成长'
    when 2 then '优质成长'
    when 3 then '合理'
    when 4 then '偏贵'
    when 5 then '负增长'
    else
      '-'
    end
  end

  def peg_level_badge_class(level)
    case level.to_i
    when 1 then 'bg-green-100 text-green-800 border-green-200'
    when 2 then 'bg-yellow-50 text-yellow-800 border-yellow-200'
    when 3 then 'bg-gray-50 text-gray-800 border-gray-200'
    when 4 then 'bg-red-50 text-red-800 border-red-200'
    when 5 then 'bg-gray-100 text-gray-800 border-gray-200'
    else
      'bg-gray-50 text-gray-500 border-gray-200'
    end
  end

  def cyclical_stock?(stock)
    names = stock.categories.map(&:name)
    keywords = %w[
      煤炭 钢铁 普钢 特钢 有色 贵金属 小金属 工业金属 能源金属
      石油 石油化工 石油天然气 油服 油气钻采
      化学 化工 化肥 农药
      水泥 建筑材料 建筑装饰 建筑
      航运 港口 航运港口 机场 高速公路 铁路运输
      房地产 房地产开发
      火电 电力 燃气 水务 公用事业
    ]
    names.any? { |n| keywords.any? { |k| n.include?(k) } }
  end

  def high_volatility_stock?(stock)
    names = stock.categories.map(&:name)
    keywords = %w[
      半导体 集成电路 电子 消费电子 电子元件 电子化学品
      IT服务 信息技术 软件 软件开发 计算机 计算机设备
      互联网 互联网信息服务 其他互联网服务 移动互联网服务
      通信 通信设备 通信服务 通信传输设备 终端设备 电商 电商服务
      新媒体 游戏 影视 传媒
      光伏 风电 电池 储能 新能源 新能源发电
      航天 航空 航空装备 航海装备 地面兵装
      医药生物 生物制品 医疗器械 医疗服务
    ]
    names.any? { |n| keywords.any? { |k| n.include?(k) } }
  end

  def tag_badge_class(tag)
    case tag.to_s
    when 'cycle'
      'bg-amber-50 text-amber-800 border-amber-200'
    when 'volatile'
      'bg-purple-50 text-purple-800 border-purple-200'
    else
      'bg-gray-50 text-gray-700 border-gray-200'
    end
  end

  def qieman_valuation_label(pe_percentile, pb_percentile)
    p = pe_percentile || pb_percentile
    return '-' if p.nil?
    v = p.to_f
    return '-' unless v.finite?
    return '低估' if v < 0.3
    return '适中' if v < 0.7
    '高估'
  end

  def qieman_valuation_badge_class(pe_percentile, pb_percentile)
    p = pe_percentile || pb_percentile
    return 'bg-gray-50 text-gray-500 border-gray-200' if p.nil?
    v = p.to_f
    return 'bg-gray-50 text-gray-500 border-gray-200' unless v.finite?
    return 'bg-green-50 text-green-700 border-green-200' if v < 0.3
    return 'bg-yellow-50 text-yellow-800 border-yellow-200' if v < 0.7
    'bg-red-50 text-red-800 border-red-200'
  end

  def qieman_sort_href(base_path, field, current_sort, current_dir)
    dir =
      if current_sort.to_s == field.to_s && current_dir.to_s == 'asc'
        'desc'
      else
        'asc'
      end
    q = Rack::Utils.build_nested_query({ sort: field, dir: dir })
    "#{base_path}?#{q}"
  end

  def pe_percentile_level_label(level)
    case level.to_i
    when 1 then '低估'
    when 2 then '正常'
    when 3 then '高估'
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
    query_params[:roe_5y_avg_ge_12] = '1' if params[:roe_5y_avg_ge_12].to_s == '1'
    query_params[:roe_5y_min_ge_8] = '1' if params[:roe_5y_min_ge_8].to_s == '1'
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
    include_pe = parse_id_list(params[:include_pe_levels]).select { |x| x >= 1 && x <= 7 }
    exclude_pe = parse_id_list(params[:exclude_pe_levels]).select { |x| x >= 1 && x <= 7 }
    query_params[:include_pe_levels] = include_pe unless include_pe.empty?
    query_params[:exclude_pe_levels] = exclude_pe unless exclude_pe.empty?
    include_pe_pct = parse_id_list(params[:include_pe_percentile_levels]).select { |x| x >= 1 && x <= 3 }
    exclude_pe_pct = parse_id_list(params[:exclude_pe_percentile_levels]).select { |x| x >= 1 && x <= 3 }
    query_params[:include_pe_percentile_levels] = include_pe_pct unless include_pe_pct.empty?
    query_params[:exclude_pe_percentile_levels] = exclude_pe_pct unless exclude_pe_pct.empty?
    include_roe_lvls = parse_id_list(params[:include_roe_levels]).select { |x| x >= 1 && x <= 3 }
    exclude_roe_lvls = parse_id_list(params[:exclude_roe_levels]).select { |x| x >= 1 && x <= 3 }
    query_params[:include_roe_levels] = include_roe_lvls unless include_roe_lvls.empty?
    query_params[:exclude_roe_levels] = exclude_roe_lvls unless exclude_roe_lvls.empty?

    "<a href='?#{build_query(query_params)}' class='hover:underline text-blue-600'>#{label}#{icon}</a>"
  end
end
