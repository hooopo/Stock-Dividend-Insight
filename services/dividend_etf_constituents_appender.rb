require 'yaml'
require_relative 'csi500_stock_appender'

class DividendEtfConstituentsAppender
  def initialize(file_path: 'stocks-pro.yml', index_ids: nil)
    @file_path = file_path
    @index_ids = Array(index_ids).compact
    @index_ids = ['000015'] if @index_ids.empty?
  end

  def run
    ensure_etf_present
    @index_ids.each do |index_id|
      Csi500StockAppender.new(file_path: @file_path, index_id: index_id.to_s, metric_prefix: "dividend_idx_#{index_id}").run
    end
  end

  private

  def ensure_etf_present
    data = YAML.load_file(@file_path)
    list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])
    exists = list.any? { |x| x['code'].to_s.rjust(6, '0') == '510880' }
    return if exists

    list << { 'code' => '510880', 'name' => '红利ETF华泰柏瑞', 'categories' => %w[ETF 红利] }

    out =
      if data.is_a?(Hash)
        data['stocks'] = list
        data.to_yaml
      else
        list.to_yaml
      end

    out = out.gsub(/^(\s*-\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    out = out.gsub(/^(\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    File.write(@file_path, out)
  end
end
