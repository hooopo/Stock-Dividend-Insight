require_relative 'csi500_stock_appender'

class FcfIndexConstituentsAppender
  def initialize(file_path: 'stocks-pro.yml', index_id: '980092')
    @file_path = file_path
    @index_id = index_id.to_s
  end

  def run
    Csi500StockAppender.new(file_path: @file_path, index_id: @index_id, metric_prefix: "fcf_idx_#{@index_id}").run
  end
end
