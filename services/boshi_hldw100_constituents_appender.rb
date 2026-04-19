require 'faraday'
require 'yaml'
require_relative 'csi500_stock_appender'

class BoshiHldw100ConstituentsAppender
  def initialize(file_path: 'stocks-pro.yml', index_id: '930955')
    @file_path = file_path
    @index_id = index_id.to_s
  end

  def run
    before_codes = load_existing_codes
    constituents = fetch_sina_index_constituent_codes
    puts "boshi_hldw100_total=#{constituents.size}"

    Csi500StockAppender.new(file_path: @file_path, index_id: @index_id, metric_prefix: "boshi_hldw100_#{@index_id}").run

    after_codes = load_existing_codes
    added = after_codes.keys - before_codes.keys
    added_in_index = added.select { |c| constituents.include?(c) }
    puts "boshi_hldw100_added=#{added_in_index.size}"
  end

  private

  def load_existing_codes
    data = YAML.load_file(@file_path)
    list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])
    list.map { |x| x['code'].to_s.rjust(6, '0') }.to_h { |c| [c, true] }
  end

  def fetch_sina_index_constituent_codes
    conn = Faraday.new do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    rows = []
    page = 1
    loop do
      url = "https://vip.stock.finance.sina.com.cn/corp/go.php/vII_NewestComponent/indexid/#{@index_id}.phtml?page=#{page}"
      resp = conn.get(url, {}, { 'User-Agent' => 'Mozilla/5.0', 'Connection' => 'close' }) do |req|
        req.options.timeout = 20
        req.options.open_timeout = 8
      end
      break unless resp.success?

      html = resp.body.to_s
      html = html.force_encoding('GBK').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      codes = html.scan(/<td><div align="center">(\d{6})<\/div><\/td>/).flatten
      break if codes.empty?

      rows.concat(codes.map { |c| c.to_s.strip.rjust(6, '0') })
      page += 1
      break if page > 40
      sleep(0.25 + rand(0.0..0.25))
    end

    rows.uniq.select { |c| c.match?(/^\d{6}$/) }
  rescue Faraday::Error
    []
  end
end
