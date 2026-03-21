require 'active_record'
require 'yaml'
require 'faraday'
require 'json'
require 'dotenv/load'
require 'shellwords'
require_relative 'models'

class StockSyncService
  API_URL = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
  
  def initialize(incremental: false)
    @incremental = incremental
  end

  def run
    load_stocks_from_yml
    sync_price_history
    sync_dividends
    sync_valuation_data
    calculate_all_yields
  end

  private

  def sync_valuation_data
    Stock.find_each do |stock|
      puts "Syncing real-time valuation for #{stock.name} (#{stock.secid})..."
      begin
        fetch_and_save_valuation(stock)
      rescue => e
        puts "Error syncing valuation for #{stock.name}: #{e.message}"
      end
      sleep(rand(0.5..1.5))
    end
  end

  def fetch_and_save_valuation(stock)
    # 尝试多个数据源，提高鲁棒性
    success = fetch_from_tencent(stock)
    success ||= fetch_from_sina(stock)
    success ||= fetch_from_eastmoney(stock)
    
    unless success
      puts "Failed to fetch valuation for #{stock.name} from all sources."
    end
  end

  def fetch_from_tencent(stock)
    # 腾讯接口: http://qt.gtimg.cn/q=s_sz000001 (简要) 或 q=sz000001 (详细)
    # 格式转换: 0.000001 -> sz000001, 1.601398 -> sh601398
    prefix = stock.secid.split('.').first == '0' ? 'sz' : 'sh'
    tencent_id = "#{prefix}#{stock.code}"
    url = "http://qt.gtimg.cn/q=#{tencent_id}"
    
    begin
      cmd = ['curl', '-s', '--connect-timeout', '5', url]
      response = `#{Shellwords.join(cmd)}`.encode('UTF-8', 'GBK', invalid: :replace, undef: :replace, replace: '')
      
      if response =~ /v_#{tencent_id}="(.*)"/
        fields = $1.split('~')
        # 腾讯接口索引: 39 是 PE, 46 是 PB
        pe = fields[39].to_f
        pb = fields[46].to_f
        
        # 允许负 PE，但 PB 必须大于 0 (正常情况下 PB 极少为负)
        if pe != 0 && pb > 0
          stock.pe = pe
          stock.pb = pb
          stock.save! if stock.changed?
          update_latest_history_valuation(stock)
          return true
        end
      end
    rescue => e
      puts "Tencent API failed for #{stock.name}: #{e.message}"
    end
    false
  end

  def fetch_from_sina(stock)
    # 新浪接口: http://finance.sina.com.cn/realstock/company/sz000001/jsvar.js
    prefix = stock.secid.split('.').first == '0' ? 'sz' : 'sh'
    sina_id = "#{prefix}#{stock.code}"
    url = "http://finance.sina.com.cn/realstock/company/#{sina_id}/jsvar.js"
    
    begin
      cmd = ['curl', '-s', '--connect-timeout', '5', url]
      response = `#{Shellwords.join(cmd)}`.encode('UTF-8', 'GBK', invalid: :replace, undef: :replace, replace: '')
      
      # 解析 JS 变量
      # var fourQ_mgsy = 2.2219; // 最近四个季度每股收益
      # var mgjzc = 23.084458; // 最近报告的每股净资产
      mgsy = response[/fourQ_mgsy\s*=\s*([\d\.]+)/, 1]&.to_f
      mgjzc = response[/mgjzc\s*=\s*([\d\.]+)/, 1]&.to_f
      
      latest_price = stock.price_histories.order(date: :desc).first&.close
      
      if mgsy && mgjzc && latest_price && mgsy != 0 && mgjzc > 0
        stock.pe = (latest_price / mgsy).round(2)
        stock.pb = (latest_price / mgjzc).round(2)
        stock.save! if stock.changed?
        update_latest_history_valuation(stock)
        return true
      end
    rescue => e
      puts "Sina API failed for #{stock.name}: #{e.message}"
    end
    false
  end

  def fetch_from_eastmoney(stock)
    url = "https://push2.eastmoney.com/api/qt/stock/get?secid=#{stock.secid}&fields=f57,f58,f162,f167,f168,f169,f170,f186&ut=fa5fd1943c7b386f172d6893dbf24410&inv=1"
    
    begin
      cmd = ['curl', '-s', '-k', '--connect-timeout', '5', url]
      response_body = `#{Shellwords.join(cmd)}`
      
      if response_body && !response_body.empty?
        data = JSON.parse(response_body).dig('data')
        if data
          pe = data['f162'].to_f / 100.0 if data['f162'] && data['f162'] != "-"
          pb = data['f167'].to_f / 100.0 if data['f167'] && data['f167'] != "-"
          
          if pe && pb && pe != 0 && pb > 0
            stock.pe = pe
            stock.pb = pb
            stock.save! if stock.changed?
            update_latest_history_valuation(stock)
            return true
          end
        end
      end
    rescue => e
      puts "Eastmoney API failed for #{stock.name}: #{e.message}"
    end
    false
  end

  def update_latest_history_valuation(stock)
    latest_history = stock.price_histories.order(date: :desc).first
    if latest_history && latest_history.date >= Date.today - 3
      latest_history.pe = stock.pe
      latest_history.pb = stock.pb
      latest_history.save!
    end
  end

  def calculate_all_yields
    puts "Calculating dividend yields for all stocks..."
    Stock.find_each do |stock|
      calculate_stock_yields(stock)
    end
  end

  def calculate_stock_yields(stock)
    latest_price = stock.price_histories.order(date: :desc).first&.close
    return if latest_price.nil? || latest_price == 0

    # 1. 预期股息率 (Expected Dividend Yield)
    # 取最近 12 个月内的所有分红累计 / 最新股价
    one_year_ago = Date.today - 365
    recent_dividends_sum = stock.dividends.where('report_date > ?', one_year_ago).sum(:cash_dividend)
    
    # 如果最近 12 个月没有，尝试取最近一个完整年度的累计
    if recent_dividends_sum == 0
      latest_dividend = stock.dividends.order(report_date: :desc).first
      if latest_dividend
        latest_year = latest_dividend.report_date.year
        recent_dividends_sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend)
      end
    end

    stock.expected_dividend_yield = (recent_dividends_sum / latest_price) * 100 if recent_dividends_sum > 0

    # 2. 历史股息率 (Dividend Yield)
    # 按照用户要求：取股票最后一次分红所属年份的累计股息率
    latest_dividend = stock.dividends.order(report_date: :desc).first
    if latest_dividend
      latest_year = latest_dividend.report_date.year
      year_dividends_sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend)
      stock.dividend_yield = (year_dividends_sum / latest_price) * 100 if year_dividends_sum > 0
    end

    # 3. 价格位置 (Price Position)
    # 位置 = (当前价 - 历史最低价) / (历史最高价 - 历史最低价)
    max_price = stock.price_histories.maximum(:high)
    min_price = stock.price_histories.minimum(:low)
    if max_price && min_price && max_price > min_price
      pos = (latest_price - min_price) / (max_price - min_price)
      stock.price_position = [[pos.to_f, 0.0].max, 1.0].min
    end

    # 4. 股息率位置 (Dividend Yield Position)
    # 股息率位置 = (当前股息率 - 历史最低股息率) / (历史最高股息率 - 历史最低股息率)
    max_yield = stock.dividends.maximum(:dividend_yield)
    min_yield = stock.dividends.minimum(:dividend_yield)
    current_yield = stock.expected_dividend_yield || stock.dividend_yield
    if max_yield && min_yield && max_yield > min_yield && current_yield
      pos = (current_yield - min_yield) / (max_yield - min_yield)
      stock.dividend_yield_position = [[pos.to_f, 0.0].max, 1.0].min
    end

    # 5. PE/PB 位置 (PE/PB Position)
    # 基于已抓取的历史数据计算百分位
    histories_with_valuation = stock.price_histories.where.not(pe: nil)
    if histories_with_valuation.count > 1
      max_pe = histories_with_valuation.maximum(:pe)
      min_pe = histories_with_valuation.minimum(:pe)
      if max_pe && min_pe && max_pe > min_pe && stock.pe && stock.pe > 0
        pos = (stock.pe - min_pe) / (max_pe - min_pe)
        stock.pe_position = [[pos.to_f, 0.0].max, 1.0].min
      end

      max_pb = histories_with_valuation.maximum(:pb)
      min_pb = histories_with_valuation.minimum(:pb)
      if max_pb && min_pb && max_pb > min_pb && stock.pb
        pos = (stock.pb - min_pb) / (max_pb - min_pb)
        stock.pb_position = [[pos.to_f, 0.0].max, 1.0].min
      end
    end

    # 6. 综合评分 (Comprehensive Position)
    # 优先使用: 0.4 * 价格位置 + 0.3 * PE位置 + 0.3 * PB位置
    # 如果 PE/PB 位置缺失，退而求其次使用红利策略: 0.5 * 价格位置 + 0.5 * (1 - 股息率位置)
    
    if stock.price_position && stock.pe_position && stock.pb_position
      stock.comprehensive_position = 0.4 * stock.price_position + 
                                     0.3 * stock.pe_position + 
                                     0.3 * stock.pb_position
    elsif stock.price_position && stock.dividend_yield_position
      stock.comprehensive_position = 0.5 * stock.price_position + 
                                     0.5 * (1 - stock.dividend_yield_position)
    end

    if stock.comprehensive_position
      # 7. 估值标签 (Valuation Label)
      pos = stock.comprehensive_position
      stock.valuation_label = if pos < 0.2
        "底部区域"
      elsif pos < 0.4
        "偏低区域"
      elsif pos < 0.6
        "中位区域"
      elsif pos < 0.8
        "偏高区域"
      else
        "高位区域"
      end
    end

    stock.save! if stock.changed?
  end

  def sync_dividends
    Stock.find_each do |stock|
      puts "Syncing dividends for #{stock.name} (#{stock.secid})..."
      begin
        fetch_and_save_dividends(stock)
      rescue => e
        puts "Error syncing dividends for #{stock.name}: #{e.message}"
      end
      sleep(rand(1.0..2.0))
    end
  end

  def fetch_and_save_dividends(stock)
    url = "https://datacenter-web.eastmoney.com/api/data/get"
    params = {
      type: "RPT_LICO_FN_CPD",
      sty: "ALL",
      filter: "(SECURITY_CODE=\"#{stock.code}\")",
      p: 1,
      ps: 50
    }

    headers = {
      'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept' => 'application/json'
    }

    conn = Faraday.new(url: url) do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    response = conn.get('', params, headers)
    
    unless response.success?
      puts "Dividend API request failed for #{stock.name}: #{response.status}"
      return
    end

    data = JSON.parse(response.body)
    results = data.dig('result', 'data') || []

    if results.empty?
      puts "No dividend data found for #{stock.name}"
      return
    end

    records_created = 0
    results.each do |item|
      # 报告期
      report_date = Date.parse(item['REPORTDATE']) rescue nil
      next unless report_date

      # 分红方案描述
      description = item['ASSIGNDSCRPT']
      next if description.nil? || description == "不分配" || description == "无分红"

      # 解析分红方案
      # 10派1.60元 -> cash_dividend = 0.16
      # 10送2转3派1.50元 -> bonus = 0.2, rights = 0.3, cash = 0.15
      base = 10.0
      if description =~ /(\d+)派|送|转/
        base = $1.to_f
      end

      cash = 0.0
      bonus = 0.0
      rights = 0.0

      if base > 0
        if description =~ /派([\d\.]+)元/
          cash = $1.to_f / base
        end
        if description =~ /送([\d\.]+)股/
          bonus = $1.to_f / base
        end
        if description =~ /转([\d\.]+)股/
          rights = $1.to_f / base
        end
      end

      div = Dividend.find_or_initialize_by(stock_id: stock.id, report_date: report_date)
      div.notice_date = Date.parse(item['NOTICE_DATE']) rescue nil
      div.plan_description = description
      
      # 确保数值字段是有限的
      div.cash_dividend = cash.finite? ? cash : 0
      div.bonus_issue = bonus.finite? ? bonus : 0
      div.rights_issue = rights.finite? ? rights : 0
      
      # 处理股息率，确保是有限数值
      yield_val = item['ZXGXL'].to_f
      div.dividend_yield = yield_val.finite? ? yield_val : nil
      
      if div.changed?
        div.save!
        records_created += 1
      end
    end
    
    puts "Saved #{records_created} dividend records for #{stock.name}."
  end

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
    # 使用东方财富 K 线接口，支持历史 PE/PB
    # 默认抓取 1000 条数据，如果是增量更新，则抓取 10 条
    limit = @incremental ? 20 : 1000
    
    # 字段含义:
    # f51: 日期, f52: 开盘, f53: 收盘, f54: 最高, f55: 最低, f56: 成交量, f57: 成交额, f58: 振幅, f59: 涨跌幅, f60: 涨跌额, f61: 换手率, f62: PE, f63: PB
    fields2 = "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63"
    
    url = "https://push2his.eastmoney.com/api/qt/stock/kline/get"
    params = {
      secid: stock.secid,
      klt: 101, # 日K
      fqt: 1,   # 前复权
      lmt: limit,
      fields1: "f1,f2,f3",
      fields2: fields2,
      ut: "fa5fd1943c7b386f172d6893dbf24410"
    }

    begin
      # 使用 curl 处理可能的 SSL 问题
      query = params.map { |k, v| "#{k}=#{v}" }.join('&')
      full_url = "#{url}?#{query}"
      
      cmd = [
        'curl', '-s', '-k',
        '--connect-timeout', '10',
        '-H', 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        full_url
      ]
      
      response_body = `#{Shellwords.join(cmd)}`
      
      if response_body && !response_body.empty?
        json_data = JSON.parse(response_body)
        klines = json_data.dig('data', 'klines') || []
        
        if klines.empty?
          puts "No kline data found for #{stock.name} from Eastmoney"
          return
        end

        records_created = 0
        klines.each do |kline_str|
          # 格式: "2024-03-22,10.50,10.60,10.70,10.40,..."
          cols = kline_str.split(',')
          date = Date.parse(cols[0]) rescue nil
          next unless date

          history = PriceHistory.find_or_initialize_by(stock_id: stock.id, date: date)
          history.open = cols[1].to_f
          history.close = cols[2].to_f
          history.high = cols[3].to_f
          history.low = cols[4].to_f
          history.volume = cols[5].to_i
          history.amount = cols[6].to_f
          history.amplitude = cols[7].to_f
          
          # 历史 PE/PB
          history.pe = cols[11].to_f if cols[11] && cols[11] != "-"
          history.pb = cols[12].to_f if cols[12] && cols[12] != "-"
          
          if history.changed?
            history.save!
            records_created += 1
          end
        end
        puts "Saved #{records_created} kline records for #{stock.name}."
      end
    rescue => e
      puts "Failed to fetch kline for #{stock.name}: #{e.message}"
    end
  end
end

if __FILE__ == $0
  incremental = ARGV.include?('--incremental')
  StockSyncService.new(incremental: incremental).run
end
