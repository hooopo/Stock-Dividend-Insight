class ValuationCalculator
  def calculate_all
    puts "Calculating yields and valuation positions for all stocks..."
    Stock.find_each do |stock|
      calculate_for_stock(stock)
    end
  end

  def calculate_for_stock(stock)
    latest_price = stock.current_price || stock.price_histories.order(date: :desc).first&.close
    return if latest_price.nil? || latest_price == 0

    # 1. 预期股息率
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

    # 2. 连续5年有分红
    current_year = Date.today.year
    years = (current_year - 5...current_year).to_a
    all_years_have_dividend = years.all? do |y|
      stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', y).where('cash_dividend > 0').exists?
    end
    stock.has_dividend_5y = all_years_have_dividend

    # 3. 价格位置
    max_price = stock.price_histories.maximum(:high)
    min_price = stock.price_histories.minimum(:low)
    if max_price && min_price
      if max_price > min_price
        pos = (latest_price - min_price) / (max_price - min_price)
        stock.price_position = [[pos.to_f, 0.0].max, 1.0].min
      else
        stock.price_position = 0.5
      end
    end

    # 4. 股息率位置
    max_yield = stock.dividends.maximum(:dividend_yield)
    min_yield = stock.dividends.minimum(:dividend_yield)
    current_yield = stock.expected_dividend_yield || stock.dividend_yield
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

    # 5. 综合评分 (基于价格位置和股息率位置)
    if stock.price_position && stock.dividend_yield_position
      stock.comprehensive_position = 0.5 * stock.price_position + 
                                     0.5 * (1 - stock.dividend_yield_position)
    elsif stock.price_position
      stock.comprehensive_position = stock.price_position
    else
      stock.comprehensive_position = 0.5
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

    stock.pb_level = pb_level_for(stock.pb)
    pb_percentile = pb_percentile_for(stock)
    stock.pb_percentile = pb_percentile
    stock.pb_percentile_level = pb_percentile_level_for(pb_percentile)

    stock.save! if stock.changed?
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
