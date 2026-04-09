require 'json'
require 'date'
require 'faraday'
require 'faraday/retry'
require_relative 'price_metrics_calculator'

class PriceHistorySyncer
  def initialize(incremental: false, force: false, scope: Stock.all, sleep_range: (1.0..3.0))
    @incremental = incremental
    @force = force
    @scope = scope
    @sleep_range = sleep_range
  end

  def sync
    @scope.find_each do |stock|
      if !@force && stock.last_synced_at && stock.last_synced_at.to_date >= Date.today
        puts "Skipping #{stock.name} (#{stock.secid}), already synced today."
        next
      end

      puts "Syncing price history for #{stock.name} (#{stock.secid})..."
      
      retries = 3
      begin
        data_present = fetch_and_save_kline(stock)
        if data_present
          PriceMetricsCalculator.calculate(stock) # 计算多维度价格指标
          stock.update!(last_synced_at: Time.now) # 标记同步成功
        else
          puts "No kline data for #{stock.name} (#{stock.secid})."
        end
      rescue Faraday::Error, JSON::ParserError => e
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
      
      sleep(rand(@sleep_range)) if @sleep_range
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
          f.request :retry, max: 3, interval: 0.05,
                           interval_randomness: 0.5, backoff_factor: 2,
                           exceptions: [Faraday::Error, JSON::ParserError]
          f.adapter Faraday.default_adapter
        end

      response = conn.get('', params, {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      })
      
      raise Faraday::Error, "HTTP #{response.status}" unless response.success?
      
      data = JSON.parse(response.body)
      return false if data.nil? || (data.respond_to?(:empty?) && data.empty?)

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
      true
    rescue Faraday::Error, JSON::ParserError => e
      puts "Failed to fetch kline for #{stock.name}: #{e.message}"
      raise e
    end
  end
end
