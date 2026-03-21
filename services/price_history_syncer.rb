require 'shellwords'
require 'json'
require 'date'
require 'faraday'

class PriceHistorySyncer
  def initialize(incremental: false)
    @incremental = incremental
  end

  def sync
    Stock.find_each do |stock|
      puts "Syncing price history for #{stock.name} (#{stock.secid})..."
      
      retries = 3
      begin
        fetch_and_save_kline(stock)
        PriceMetricsCalculator.calculate(stock) # 计算多维度价格指标
      rescue => e
        if retries > 0
          retries -= 1
          wait_time = (4 - retries) * 5 + rand(1..3)
          puts "Network error syncing #{stock.name}: #{e.message}. Retrying in #{wait_time}s... (#{retries} left)"
          sleep(wait_time)
          retry
        else
          puts "Failed to sync #{stock.name} after retries due to network error: #{e.message}"
        end
      end
      
      sleep(rand(1.0..3.0))
    end
  end

  private

  def fetch_and_save_kline(stock)
    # 转换 secid 为新浪格式 (例如 1.601398 -> sh601398)
    market_prefix = stock.market_id == 1 ? 'sh' : 'sz'
    symbol = "#{market_prefix}#{stock.code}"
    
    # 默认抓取 2600 条数据 (约 10 年交易日)，如果是增量更新，则抓取 20 条
    datalen = @incremental ? 20 : 2600

    url = "https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData"
    params = {
      symbol: symbol,
      scale: 240, # 日K
      ma: 'no',
      datalen: datalen
    }

    begin
      conn = Faraday.new(url: url) do |f|
        f.request :url_encoded
        f.adapter Faraday.default_adapter
      end

      response = conn.get('', params, {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      })
      
      return unless response.success?
      
      data = JSON.parse(response.body)
      return if data.empty?

      records_created = 0
      data.each do |item|
        # 新浪 API 返回格式: {"day":"2026-03-20","open":"10.870","high":"10.940","low":"10.760","close":"10.770","volume":"83408256"}
        date = Date.parse(item['day']) rescue nil
        next unless date

        history = PriceHistory.find_or_initialize_by(stock_id: stock.id, date: date)
        history.open = item['open'].to_f
        history.close = item['close'].to_f
        history.high = item['high'].to_f
        history.low = item['low'].to_f
        history.volume = item['volume'].to_i
        
        if history.changed?
          history.save!
          records_created += 1
        end
      end
      puts "Saved #{records_created} kline records for #{stock.name}."
    rescue => e
      puts "Failed to fetch kline for #{stock.name}: #{e.message}"
      raise e
    end
  end
end
