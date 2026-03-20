require 'active_record'
require 'yaml'
require 'faraday'
require 'json'
require_relative 'models'

# 数据库配置
ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  database: 'stock_dividend_insight'
)

class StockSyncService
  API_URL = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
  
  def initialize(incremental: false)
    @incremental = incremental
  end

  def run
    load_stocks_from_yml
    sync_price_history
  end

  private

  def load_stocks_from_yml
    puts "Loading stocks from stocks.yml..."
    stocks_data = YAML.load_file('stocks.yml')
    
    stocks_data.each do |data|
      next unless data['secid'] && data['name']
      
      market_id, code = data['secid'].split('.')
      
      Stock.find_or_create_by!(secid: data['secid']) do |s|
        s.name = data['name']
        s.market_id = market_id.to_i
        s.code = code
      end
    end
    puts "Loaded #{Stock.count} stocks."
  end

  def sync_price_history
    Stock.find_each do |stock|
      puts "Syncing price history for #{stock.name} (#{stock.secid})..."
      
      retries = 3
      begin
        fetch_and_save_kline(stock)
      rescue Faraday::ConnectionFailed, Faraday::TimeoutError, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
        if retries > 0
          retries -= 1
          wait_time = (4 - retries) * 5 + rand(1..3)
          puts "Network error syncing #{stock.name}: #{e.message}. Retrying in #{wait_time}s... (#{retries} left)"
          sleep(wait_time)
          retry
        else
          puts "Failed to sync #{stock.name} after retries due to network error: #{e.message}"
        end
      rescue => e
        puts "Error syncing #{stock.name}: #{e.message}"
      end
      
      # 频率控制，增加随机性
      sleep_time = rand(1.0..3.0)
      sleep(sleep_time)
    end
  end

  def fetch_and_save_kline(stock)
    # 转换 secid 为新浪格式 (例如 1.601398 -> sh601398)
    market_prefix = stock.market_id == 1 ? 'sh' : 'sz'
    symbol = "#{market_prefix}#{stock.code}"
    
    # 默认抓取 1000 条数据，如果是增量更新，则抓取 10 条
    datalen = @incremental ? 10 : 1000

    url = "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData"
    params = {
      symbol: symbol,
      scale: 240, # 日K
      ma: 'no',
      datalen: datalen
    }

    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => '*/*'
    }

    conn = Faraday.new(url: url) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    response = conn.get('', params, headers)
    
    unless response.success?
      puts "Sina API request failed for #{stock.name}: #{response.status}"
      return
    end

    begin
      # 新浪返回的是 GBK 编码或者 JSON 字符串
      data = JSON.parse(response.body)
    rescue => e
      puts "Failed to parse JSON for #{stock.name}: #{e.message}"
      return
    end

    if data.empty?
      puts "No kline data found for #{stock.name}"
      return
    end

    records_created = 0
    data.each do |item|
      # 格式: {"day":"2026-03-20","open":"10.870","high":"10.940","low":"10.760","close":"10.770","volume":"83408256"}
      date = Date.parse(item['day'])
      
      ph = PriceHistory.find_or_initialize_by(stock_id: stock.id, date: date)
      ph.open = item['open'].to_f
      ph.close = item['close'].to_f
      ph.high = item['high'].to_f
      ph.low = item['low'].to_f
      ph.volume = item['volume'].to_i
      
      if ph.changed?
        ph.save!
        records_created += 1
      end
    end
    
    puts "Saved #{records_created} records for #{stock.name}."
  end
end

if __FILE__ == $0
  incremental = ARGV.include?('--incremental')
  StockSyncService.new(incremental: incremental).run
end
