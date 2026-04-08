require 'yaml'

class StockLoader
  def initialize(file_path = 'stocks-pro.yml')
    @file_path = file_path
  end

  def verify_codes_and_repair_histories!
    require 'faraday'
    require 'json'
    require_relative 'price_history_syncer'
    require_relative 'price_metrics_calculator'
    require_relative 'dividend_syncer'
    require_relative 'valuation_calculator'

    url_sina = 'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData'
    url_em = 'https://searchapi.eastmoney.com/api/suggest/get'

    data = YAML.load_file(@file_path)
    list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])

    entries_by_name = Hash.new { |h, k| h[k] = [] }
    list.each_with_index do |s, i|
      name = s['name'].to_s.strip
      next if name.empty?
      entries_by_name[name] << i
    end

    conn = Faraday.new do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    changed = []
    unresolved = []

    entries_by_name.each do |name, idxs|
      sample = list[idxs.first]
      current_code = sample['code'].to_s.strip.rjust(6, '0')
      current_market_id = current_code.start_with?('6') ? 1 : 0

      em = em_lookup(conn, url_em, name, current_code)
      unless em
        if sina_ok?(conn, url_sina, current_market_id, current_code)
          unresolved << [name, current_code, nil, 'no_eastmoney_match_but_sina_ok']
        else
          unresolved << [name, current_code, nil, 'no_eastmoney_match_and_sina_null']
        end
        next
      end

      em_code = em['Code'].to_s.strip
      em_quote = em['QuoteID'].to_s
      em_market_id = em_quote.split('.').first.to_i

      if em_code.match?(/^\d{6}$/) && em_quote.match?(/^[01]\.\d{6}$/)
        if em_code != current_code
          if sina_ok?(conn, url_sina, em_market_id, em_code)
            idxs.each { |i| list[i]['code'] = em_code }
            changed << [name, current_code, em_code]
          else
            unresolved << [name, current_code, em_code, 'eastmoney_code_sina_null']
            next
          end
        end
      else
        unresolved << [name, current_code, em_code, 'bad_eastmoney_payload']
        next
      end

      final_code = list[idxs.first]['code'].to_s.strip.rjust(6, '0')
      final_market_id = final_code.start_with?('6') ? 1 : 0
      unless sina_ok?(conn, url_sina, final_market_id, final_code)
        unresolved << [name, final_code, em_code, 'sina_null_after']
      end
    end

    if data.is_a?(Hash)
      data['stocks'] = list
      out = data.to_yaml
    else
      out = list.to_yaml
    end

    out = out.gsub(/^(\s*-\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    out = out.gsub(/^(\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    File.write(@file_path, out)

    puts "verify_total=#{entries_by_name.size}"
    puts "verify_changed=#{changed.map { |x| x[0] }.uniq.size}"
    changed.uniq.each { |c| puts c.join("\t") }
    puts "verify_unresolved=#{unresolved.uniq.size}"
    unresolved.uniq.first(50).each { |u| puts u.join("\t") }
    puts "...truncated" if unresolved.uniq.size > 50

    load

    changed_names = changed.map { |x| x[0] }.uniq
    changed_names.each do |name|
      stock = Stock.find_by(name: name)
      next unless stock

      PriceHistory.where(stock_id: stock.id).delete_all
      Dividend.where(stock_id: stock.id).delete_all
      stock.update!(last_synced_at: nil)

      PriceHistorySyncer.new(incremental: false, force: true, scope: Stock.where(id: stock.id), sleep_range: nil).sync
      DividendSyncer.new(scope: Stock.where(id: stock.id), sleep_range: nil).sync
      ValuationCalculator.new.calculate_for_stock(stock)
    end
  end

  def load
    puts "Loading stocks from #{@file_path}..."
    data = YAML.load_file(@file_path)
    stocks_data = data.is_a?(Hash) ? data['stocks'] : data
    desired_secids = []
    desired_category_names = []
    desired_by_code = {}
    desired_by_name = {}
    desired_categories_by_secid = Hash.new { |h, k| h[k] = [] }

    stocks_data.each do |stock_data|
      name = stock_data['name']&.to_s
      code = stock_data['code']&.to_s
      secid = stock_data['secid']&.to_s

      next unless (code || secid) && name

      market_id = nil
      if code && !secid
        code = code.rjust(6, '0')
        market_id = code.start_with?('6') ? 1 : 0
        secid = "#{market_id}.#{code}"
      elsif secid
        market_id, code = secid.split('.')
        market_id = market_id.to_i
        code = code.to_s.rjust(6, '0')
        secid = "#{market_id}.#{code}"
      end

      next unless market_id && code && secid

      desired_by_code[[market_id, code]] = secid
      desired_by_name[name] = secid

      categories = Array(stock_data['categories'])
                   .map { |c| c.to_s.strip }
                   .reject(&:empty?)
                   .uniq
      desired_category_names.concat(categories)
      desired_categories_by_secid[secid].concat(categories)
    end
    
    stocks_data.reverse.each do |stock_data|
      name = stock_data['name']
      code = stock_data['code']&.to_s
      secid = stock_data['secid']
      
      next unless (code || secid) && name
      
      market_id = nil

      if code && !secid
        code = code.rjust(6, '0')
        if code.start_with?('6')
          market_id = 1
          secid = "1.#{code}"
        else
          market_id = 0
          secid = "0.#{code}"
        end
      elsif secid
        market_id, code = secid.split('.')
        market_id = market_id.to_i
        code = code.to_s.rjust(6, '0')
        secid = "#{market_id}.#{code}"
      end

      desired_secids << secid
      
      stock = Stock.find_by(secid: secid)
      stock ||= Stock.find_by(market_id: market_id, code: code)
      stock ||= Stock.where(name: name).order(:id).first

      if stock
        stock.update!(secid: secid, name: name, market_id: market_id, code: code)
      else
        stock = Stock.create!(secid: secid, name: name, market_id: market_id, code: code)
      end

      Stock.where(name: name).where.not(id: stock.id).find_each do |dup|
        conn = ActiveRecord::Base.connection
        from_id = dup.id
        to_id = stock.id

        if dup.market_id != stock.market_id || dup.code != stock.code
          PriceHistory.where(stock_id: from_id).delete_all
          Dividend.where(stock_id: from_id).delete_all
          Categorization.where(stock_id: from_id).delete_all
          dup.destroy!
          next
        end

        conn.execute(<<~SQL)
          INSERT INTO price_histories (stock_id, date, open, close, high, low, volume, created_at, updated_at)
          SELECT #{to_id}, date, open, close, high, low, volume, created_at, updated_at
          FROM price_histories
          WHERE stock_id = #{from_id}
          ON CONFLICT (stock_id, date) DO NOTHING;
        SQL
        conn.execute("DELETE FROM price_histories WHERE stock_id = #{from_id}")

        conn.execute(<<~SQL)
          INSERT INTO dividends (stock_id, report_date, notice_date, plan_description, cash_dividend, bonus_issue, rights_issue, dividend_yield, created_at, updated_at)
          SELECT #{to_id}, report_date, notice_date, plan_description, cash_dividend, bonus_issue, rights_issue, dividend_yield, created_at, updated_at
          FROM dividends
          WHERE stock_id = #{from_id}
          ON CONFLICT (stock_id, report_date) DO NOTHING;
        SQL
        conn.execute("DELETE FROM dividends WHERE stock_id = #{from_id}")

        conn.execute(<<~SQL)
          INSERT INTO categorizations (stock_id, category_id, created_at, updated_at)
          SELECT #{to_id}, category_id, created_at, updated_at
          FROM categorizations
          WHERE stock_id = #{from_id}
          ON CONFLICT (stock_id, category_id) DO NOTHING;
        SQL
        conn.execute("DELETE FROM categorizations WHERE stock_id = #{from_id}")
        dup.destroy!
      end
      
      # 同步分类
      # 先清除旧关联，以 YML 为准
      stock.categorizations.destroy_all

      categories = desired_categories_by_secid[secid]
                   .map { |c| c.to_s.strip }
                   .reject(&:empty?)
                   .uniq

      categories.each do |cat_name|
        category = Category.find_or_create_by!(name: cat_name)
        Categorization.find_or_create_by!(stock: stock, category: category)
      end
    end

    desired_secids = desired_secids.uniq
    Stock.where.not(secid: desired_secids).find_each do |s|
      target_secid = desired_by_code[[s.market_id, s.code]] || desired_by_name[s.name]

      if target_secid
        target = Stock.find_by(secid: target_secid)
        if target && target.id != s.id
          if s.market_id != target.market_id || s.code != target.code
            PriceHistory.where(stock_id: s.id).delete_all
            Dividend.where(stock_id: s.id).delete_all
            Categorization.where(stock_id: s.id).delete_all
            s.destroy!
            next
          end

          conn = ActiveRecord::Base.connection
          from_id = s.id
          to_id = target.id

          conn.execute(<<~SQL)
            INSERT INTO price_histories (stock_id, date, open, close, high, low, volume, created_at, updated_at)
            SELECT #{to_id}, date, open, close, high, low, volume, created_at, updated_at
            FROM price_histories
            WHERE stock_id = #{from_id}
            ON CONFLICT (stock_id, date) DO NOTHING;
          SQL
          conn.execute("DELETE FROM price_histories WHERE stock_id = #{from_id}")

          conn.execute(<<~SQL)
            INSERT INTO dividends (stock_id, report_date, notice_date, plan_description, cash_dividend, bonus_issue, rights_issue, dividend_yield, created_at, updated_at)
            SELECT #{to_id}, report_date, notice_date, plan_description, cash_dividend, bonus_issue, rights_issue, dividend_yield, created_at, updated_at
            FROM dividends
            WHERE stock_id = #{from_id}
            ON CONFLICT (stock_id, report_date) DO NOTHING;
          SQL
          conn.execute("DELETE FROM dividends WHERE stock_id = #{from_id}")

          conn.execute(<<~SQL)
            INSERT INTO categorizations (stock_id, category_id, created_at, updated_at)
            SELECT #{to_id}, category_id, created_at, updated_at
            FROM categorizations
            WHERE stock_id = #{from_id}
            ON CONFLICT (stock_id, category_id) DO NOTHING;
          SQL
          conn.execute("DELETE FROM categorizations WHERE stock_id = #{from_id}")
        end
      end

      s.destroy!
    end

    desired_category_names = desired_category_names.map(&:to_s).map(&:strip).reject(&:empty?).uniq

    Category.where("name <> btrim(name)").find_each do |cat|
      normalized = cat.name.to_s.strip
      next if normalized.empty?

      target = Category.find_by(name: normalized)
      if target && target.id != cat.id
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO categorizations (stock_id, category_id, created_at, updated_at)
          SELECT stock_id, #{target.id}, created_at, updated_at
          FROM categorizations
          WHERE category_id = #{cat.id}
          ON CONFLICT (stock_id, category_id) DO NOTHING;
        SQL
        Categorization.where(category_id: cat.id).delete_all
        cat.destroy!
      else
        cat.update!(name: normalized)
      end
    end

    Category.where.not(name: desired_category_names).left_joins(:categorizations).where(categorizations: { id: nil }).find_each do |cat|
      cat.destroy!
    end

    Category.left_joins(:categorizations).where(categorizations: { id: nil }).find_each do |cat|
      cat.destroy!
    end

    puts "Loaded #{Stock.count} stocks."
  end

  private

  def sina_ok?(conn, url_sina, market_id, code)
    symbol = (market_id.to_i == 1 ? 'sh' : 'sz') + code
    3.times do
      response = conn.get(url_sina, { symbol: symbol, scale: 240, ma: 'no', datalen: 5 }, { 'User-Agent' => 'Mozilla/5.0' }) do |req|
        req.options.timeout = 8
        req.options.open_timeout = 5
      end
      body = response.body.to_s.strip
      return false unless response.status == 200
      return false if body == 'null' || body == '' || body == '[]'
      parsed = JSON.parse(body) rescue nil
      return false if parsed.nil? || (parsed.respond_to?(:empty?) && parsed.empty?)
      return true
    rescue Faraday::Error
      sleep(0.2)
      next
    end
    false
  rescue Faraday::Error
    false
  end

  def em_lookup(conn, url_em, name, code)
    rows = em_suggest_rows(conn, url_em, name)
    if rows && !rows.empty?
      exact = rows.find { |x| x['Name'].to_s == name }
      return exact if exact

      by_code = rows.find { |x| x['Code'].to_s == code }
      return by_code if by_code

      return rows.first
    end

    rows = em_suggest_rows(conn, url_em, code)
    if rows && !rows.empty?
      by_code = rows.find { |x| x['Code'].to_s == code }
      return by_code if by_code
    end

    nil
  end

  def em_suggest_rows(conn, url_em, input)
    response = conn.get(url_em, { input: input, type: 14, count: 10 }, { 'User-Agent' => 'Mozilla/5.0' }) do |req|
      req.options.timeout = 8
      req.options.open_timeout = 5
    end
    return nil unless response.status == 200
    parsed = JSON.parse(response.body) rescue nil
    rows = parsed && parsed.dig('QuotationCodeTable', 'Data')
    return nil unless rows && !rows.empty?
    rows.select do |x|
      x['Code'].to_s.match?(/^\d{6}$/) &&
        x['QuoteID'].to_s.match?(/^[01]\.\d{6}$/) &&
        x['SecurityTypeName'].to_s.match?(/沪A|深A|科创|创业|北A|京A/)
    end
  rescue Faraday::Error
    nil
  end
end
