require 'yaml'

class StockLoader
  def initialize(file_path = 'stocks-pro.yml')
    @file_path = file_path
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
end
