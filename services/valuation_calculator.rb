class ValuationCalculator
  def calculate_all
    puts "Calculating yields and valuation positions for all stocks..."
    Stock.where(asset_type: 'stock').find_each do |stock|
      calculate_for_stock(stock)
    end
  end

  def calculate_for_stock(stock)
    latest_history = stock.price_histories.order(date: :desc).first
    latest_price = stock.current_price || latest_history&.close
    return if latest_price.nil? || latest_price == 0
    base_date = latest_history&.date

    if stock.asset_type == 'stock'
      one_year_ago = Date.today - 365
      recent_dividends_sum = stock.dividends.where('report_date > ?', one_year_ago).sum(:cash_dividend)
      
      if recent_dividends_sum == 0
        latest_dividend = stock.dividends.order(report_date: :desc).first
        if latest_dividend
          latest_year = latest_dividend.report_date.year
          recent_dividends_sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend)
        end
      end
      if recent_dividends_sum > 0
        stock.expected_dividend_yield = (recent_dividends_sum / latest_price) * 100
      else
        stock.expected_dividend_yield = 0.0
      end

      latest_dividend = stock.dividends.order(report_date: :desc).first
      if latest_dividend
        latest_year = latest_dividend.report_date.year
        year_sum = stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend)
        stock.dividend_yield = year_sum.to_f > 0 ? (year_sum / latest_price) * 100 : 0.0
      else
        stock.dividend_yield = 0.0
      end

      current_year = Date.today.year
      years = (current_year - 5...current_year).to_a
      all_years_have_dividend = years.all? do |y|
        stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', y).where('cash_dividend > 0').exists?
      end
      stock.has_dividend_5y = all_years_have_dividend
    else
      stock.expected_dividend_yield = nil
      stock.dividend_yield = nil
      stock.has_dividend_5y = false
      stock.dividend_yield_position = nil
      stock.comprehensive_position = stock.price_position || 0.5
    end

    # 3. 价格位置
    if base_date
      from_date = base_date << 120
      closes = stock.price_histories.where('date >= ?', from_date).where.not(close: nil).pluck(:close)
      stock.price_position = percentile_for(latest_price, closes)
      update_rolling_price_metrics(stock, base_date, latest_price)
    end

    if stock.asset_type == 'stock'
      max_yield = stock.dividends.maximum(:dividend_yield)
      min_yield = stock.dividends.minimum(:dividend_yield)
      current_yield = stock.dividend_yield
      if current_yield
        if max_yield && min_yield
          if max_yield > min_yield
            pos = (current_yield - min_yield) / (max_yield - min_yield)
            stock.dividend_yield_position = [[pos.to_f, 0.0].max, 1.0].min
          else
            stock.dividend_yield_position = 0.5
          end
        else
          stock.dividend_yield_position = 0.5
        end
      end

      if stock.price_position && stock.dividend_yield_position
        stock.comprehensive_position = 0.5 * stock.price_position + 
                                       0.5 * (1 - stock.dividend_yield_position)
      elsif stock.price_position
        stock.comprehensive_position = stock.price_position
      else
        stock.comprehensive_position = 0.5
      end
    end

    if stock.comprehensive_position
      # 7. 估值标签
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

    if stock.pb.nil? || stock.pb.to_f <= 0
      latest_pb = stock.price_histories.where.not(pb: nil).order(date: :desc).limit(1).pluck(:pb).first
      stock.pb = latest_pb if latest_pb && latest_pb.to_f > 0
    end

    if stock.pe_ttm.nil? || stock.pe_ttm.to_f <= 0
      latest_pe = stock.price_histories.where.not(pe_ttm: nil).order(date: :desc).limit(1).pluck(:pe_ttm).first
      stock.pe_ttm = latest_pe if latest_pe && latest_pe.to_f > 0
    end

    stock.pb_level = pb_level_for(stock.pb)
    pb_percentile = pb_percentile_for(stock)
    stock.pb_percentile = pb_percentile
    stock.pb_percentile_level = pb_percentile_level_for(pb_percentile)

    stock.pe_level = pe_level_for(stock.pe_ttm)
    pe_percentile = pe_percentile_for(stock)
    stock.pe_percentile = pe_percentile
    stock.pe_percentile_level = pe_percentile_level_for(pe_percentile)

    stock.save! if stock.changed?
  end

  def update_rolling_price_metrics(stock, base_date, base_price)
    update_window(stock, '30d', 30, base_date, base_price)
    update_window(stock, '1y', 365, base_date, base_price)
    update_window(stock, '3y', 1095, base_date, base_price)
    update_window(stock, '5y', 1825, base_date, base_price)
  end

  def update_window(stock, suffix, days, base_date, base_price)
    start_date = base_date - days
    scope = stock.price_histories.where('date >= ? AND date <= ?', start_date, base_date)

    high = scope.maximum(:high)
    low = scope.minimum(:low)
    if high && low
      stock.send("high_#{suffix}=", high)
      stock.send("low_#{suffix}=", low)
    end

    closes = scope.where.not(close: nil).pluck(:close)
    stock.send("pos_#{suffix}=", percentile_for(base_price, closes))
  end

  def percentile_for(current, arr)
    return nil if current.nil?
    c = current.to_f
    return nil unless c.finite? && c > 0

    values = Array(arr).map { |x| x.to_f }.select { |x| x.finite? && x > 0 }
    return nil if values.empty?
    return 0.5 if values.size <= 1

    sorted = values.sort
    idx = sorted.bsearch_index { |x| x >= c } || (sorted.size - 1)
    p = idx.to_f / (sorted.size - 1).to_f
    [[p, 0.0].max, 1.0].min
  end

  def pb_percentile_for(stock)
    pb = stock.pb
    return nil if pb.nil?
    current = pb.to_f
    return nil unless current.finite? && current > 0

    from_date = Date.today << 120
    arr = stock.price_histories.where('date >= ?', from_date).where.not(pb: nil).pluck(:pb).map { |x| x.to_f }.select { |x| x.finite? && x > 0 }
    return nil if arr.size < 20

    sorted = arr.sort
    idx = sorted.bsearch_index { |x| x >= current } || (sorted.size - 1)

    if sorted.size <= 1
      0.5
    else
      (idx.to_f / (sorted.size - 1).to_f)
    end
  end

  def pb_percentile_level_for(p)
    return nil if p.nil?
    v = p.to_f
    return nil unless v.finite?
    return 1 if v < 0.2
    return 2 if v < 0.5
    return 3 if v < 0.8
    4
  end

  def pe_percentile_for(stock)
    pe = stock.pe_ttm
    return nil if pe.nil?
    current = pe.to_f
    return nil unless current.finite? && current > 0

    from_date = Date.today << 120
    arr = stock.price_histories.where('date >= ?', from_date).where.not(pe_ttm: nil).pluck(:pe_ttm).map { |x| x.to_f }.select { |x| x.finite? && x > 0 }
    return nil if arr.size < 20

    sorted = arr.sort
    idx = sorted.bsearch_index { |x| x >= current } || (sorted.size - 1)

    if sorted.size <= 1
      0.5
    else
      (idx.to_f / (sorted.size - 1).to_f)
    end
  end

  def pe_percentile_level_for(p)
    return nil if p.nil?
    v = p.to_f
    return nil unless v.finite?
    return 1 if v < 0.3
    return 2 if v < 0.7
    3
  end

  def pe_level_for(pe_ttm)
    return nil if pe_ttm.nil?
    v = pe_ttm.to_f
    return nil unless v.finite?

    return 1 if v < 0
    return 2 if v < 10
    return 3 if v < 20
    return 4 if v < 30
    return 5 if v < 50
    return 6 if v < 100
    7
  end

  def pb_level_for(pb)
    return nil if pb.nil?
    v = pb.to_f
    return nil unless v.finite? && v > 0

    return 1 if v <= 0.8
    return 2 if v <= 1.5
    return 3 if v <= 3
    return 4 if v <= 6
    return 5 if v <= 10
    6
  end
end
