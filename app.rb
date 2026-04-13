require 'date'
require 'sinatra'
require 'sinatra/reloader' if development?
require_relative 'models'
require_relative 'services/valuation_history_syncer'

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

get '/' do
  allowed_sort_fields = %w[
    current_price dividend_yield
    turnover_rate volume pe_ttm pe_level pe_percentile pb pb_level pb_percentile roe_jq roe_level total_shares
    pos_30d pos_1y pos_3y pos_5y price_position
  ]
  
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
  roe_5y_avg_ge_12 = params[:roe_5y_avg_ge_12].to_s == '1'
  roe_5y_min_ge_8 = params[:roe_5y_min_ge_8].to_s == '1'
  roe_min = nil
  roe_max = nil
  include_roe_levels = parse_id_list(params[:include_roe_levels]).select { |x| x >= 1 && x <= 3 }
  exclude_roe_levels = parse_id_list(params[:exclude_roe_levels]).select { |x| x >= 1 && x <= 3 }

  sorts = parse_sorts_param(params[:sort], allowed_sort_fields)

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

    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
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

    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_include = params[:remove_include_category_id].to_s.strip).size > 0
    include_category_ids = include_category_ids.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
    query_params[:only_div5y] = '1' if only_div5y
    query_params[:roe_5y_avg_ge_12] = '1' if roe_5y_avg_ge_12
    query_params[:roe_5y_min_ge_8] = '1' if roe_5y_min_ge_8
    query_params[:include_category_ids] = include_category_ids unless include_category_ids.empty?
    query_params[:exclude_category_ids] = exclude_category_ids unless exclude_category_ids.empty?
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_category_id].to_s.strip).size > 0
    exclude_category_ids = exclude_category_ids.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_include = params[:remove_include_pb_level].to_s.strip).size > 0
    include_pb_levels = include_pb_levels.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_pb_level].to_s.strip).size > 0
    exclude_pb_levels = exclude_pb_levels.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_include = params[:remove_include_pb_percentile_level].to_s.strip).size > 0
    include_pb_percentile_levels = include_pb_percentile_levels.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_pb_percentile_level].to_s.strip).size > 0
    exclude_pb_percentile_levels = exclude_pb_percentile_levels.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_include = params[:remove_include_pe_level].to_s.strip).size > 0
    include_pe_levels = include_pe_levels.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_pe_level].to_s.strip).size > 0
    exclude_pe_levels = exclude_pe_levels.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_include = params[:remove_include_pe_percentile_level].to_s.strip).size > 0
    include_pe_percentile_levels = include_pe_percentile_levels.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_exclude = params[:remove_exclude_pe_percentile_level].to_s.strip).size > 0
    exclude_pe_percentile_levels = exclude_pe_percentile_levels.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end

  if (remove_sort = params[:remove_sort].to_s.strip).size > 0
    sorts = sorts.reject { |s| s[:field] == remove_sort }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end
  if (remove_include = params[:remove_include_roe_level].to_s.strip).size > 0
    include_roe_levels = include_roe_levels.reject { |x| x == remove_include.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end
  if (remove_exclude = params[:remove_exclude_roe_level].to_s.strip).size > 0
    exclude_roe_levels = exclude_roe_levels.reject { |x| x == remove_exclude.to_i }
    query_params = { sort: serialize_sorts_param(sorts) }
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
    query_params[:include_roe_levels] = include_roe_levels unless include_roe_levels.empty?
    query_params[:exclude_roe_levels] = exclude_roe_levels unless exclude_roe_levels.empty?
    query_params[:roe_min] = roe_min if roe_min
    query_params[:roe_max] = roe_max if roe_max
    redirect "/?#{Rack::Utils.build_query(query_params)}"
  end
  if params[:clear_sorts].to_s == '1'
    redirect '/'
  end

  base_scope = Stock.includes(:categories)
  if only_div5y
    base_scope = base_scope.where(has_dividend_5y: true)
  end
  if roe_5y_avg_ge_12
    base_scope = base_scope.where(roe_5y_avg_ge_12: true)
  end
  if roe_5y_min_ge_8
    base_scope = base_scope.where(roe_5y_min_ge_8: true)
  end
  if include_roe_levels.any?
    base_scope = base_scope.where(roe_level: include_roe_levels)
  end
  if exclude_roe_levels.any?
    base_scope = base_scope.where.not(roe_level: exclude_roe_levels)
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
  if include_pe_levels.any?
    base_scope = base_scope.where(pe_level: include_pe_levels)
  end
  if exclude_pe_levels.any?
    base_scope = base_scope.where.not(pe_level: exclude_pe_levels)
  end
  if include_pe_percentile_levels.any?
    base_scope = base_scope.where(pe_percentile_level: include_pe_percentile_levels)
  end
  if exclude_pe_percentile_levels.any?
    base_scope = base_scope.where.not(pe_percentile_level: exclude_pe_percentile_levels)
  end
  sorts.each do |s|
    if s[:field] == 'pe_ttm' && s[:order] == 'asc'
      base_scope = base_scope.where('pe_ttm > 0')
    end
  end

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
  @include_roe_levels = include_roe_levels
  @exclude_roe_levels = exclude_roe_levels
  @allowed_sort_fields = allowed_sort_fields
  @sorts = sorts
  @sort_param = serialize_sorts_param(sorts)
  @only_div5y = only_div5y
  @roe_5y_avg_ge_12 = roe_5y_avg_ge_12
  @roe_5y_min_ge_8 = roe_5y_min_ge_8
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

get '/kb/pe' do
  erb :kb_pe
end

get '/kb/roe' do
  erb :kb_roe
end

get '/kb/dividend' do
  erb :kb_dividend
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
    Rack::Utils.build_query(params_hash.reject { |_, v| v.nil? || v.to_s.empty? })
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
      'pe_level' => 'PE等级',
      'pe_percentile' => 'PE历史分位',
      'pb' => 'PB',
      'pb_level' => 'PB等级',
      'pb_percentile' => 'PB历史分位',
      'roe_jq' => 'ROE(加权)',
      'roe_level' => 'ROE等级',
      'total_shares' => '总股本',
      'pos_30d' => '30d分位',
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
