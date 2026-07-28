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
      latest_dividend = stock.dividends.order(report_date: :desc).first
      latest_year = latest_dividend&.report_date&.year
      year_sum =
        if latest_year
          stock.dividends.where('EXTRACT(YEAR FROM report_date) = ?', latest_year).sum(:cash_dividend).to_f
        else
          0.0
        end

      if year_sum > 0
        stock.expected_dividend_yield = (year_sum / latest_price) * 100
        stock.dividend_yield = stock.expected_dividend_yield
      else
        stock.expected_dividend_yield = 0.0
        stock.dividend_yield = 0.0
      end

      current_year = Date.today.year
      years = (current_year - 5...current_year).to_a
      all_years_have_dividend =
        years.all? do |y|
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
      history_scope = stock.price_histories.where('date >= ?', from_date)
      stock.high_all = history_scope.maximum(:high)
      stock.low_all = history_scope.minimum(:low)
      closes = history_scope.where.not(close: nil).pluck(:close)
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

    if stock.asset_type == 'stock' && stock.dividend_yield && stock.pe_ttm && stock.pe_ttm.to_f > 0 && stock.dividend_yield.to_f >= 0
      stock.dividend_payout_ratio = stock.dividend_yield.to_f * stock.pe_ttm.to_f
    else
      stock.dividend_payout_ratio = nil
    end

    stock.pb_level = pb_level_for(stock.pb)
    pb_percentile = pb_percentile_for(stock)
    stock.pb_percentile = pb_percentile
    stock.pb_percentile_level = pb_percentile_level_for(pb_percentile)

    stock.pe_level = pe_level_for(stock.pe_ttm)
    pe_percentile = pe_percentile_for(stock)
    stock.pe_percentile = pe_percentile
    stock.pe_percentile_level = pe_percentile_level_for(pe_percentile)

    stock.buy_score = compute_buy_score(stock) if stock.has_attribute?(:buy_score)
    stock.save! if stock.changed?
  end

  def update_rolling_price_metrics(stock, base_date, base_price)
    update_window(stock, '30d', 30, base_date, base_price)
    update_window(stock, '90d', 90, base_date, base_price)
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

  def compute_buy_score(stock)
    weights = {
      dividend_payout_ratio: 0.15,
      pe_level: 0.15,
      pb_level: 0.15,
      peg_level: 0.10,
      asset_liability_ratio: 0.10,
      fcf_yield: 0.10,
      roe_level: 0.15,
      price_position: 0.10
    }

    s = 0.0
    s += weights[:dividend_payout_ratio] * score_dividend_payout_ratio(stock.dividend_payout_ratio)
    s += weights[:pe_level] * score_pe_level(stock.pe_level)
    s += weights[:pb_level] * score_pb_level(stock.pb_level)
    s += weights[:peg_level] * score_peg_level(stock.peg_level)
    s += weights[:asset_liability_ratio] * score_asset_liability_ratio(stock.asset_liability_ratio)
    s += weights[:fcf_yield] * score_fcf_yield(stock.fcf_yield)
    s += weights[:roe_level] * score_roe_level(stock.roe_level)
    s += weights[:price_position] * score_price_position(stock.price_position)

    raw = 1.0 + 4.0 * clamp01(s)
    rounded = (clamp(raw, 1.0, 5.0) * 2.0).round / 2.0
    clamp(rounded, 1.0, 5.0).round(2)
  end

  def score_dividend_payout_ratio(value)
    return 0.5 if value.nil?
    r = value.to_f
    return 0.5 unless r.finite?
    return 0.3 if r <= 0
    return 0.6 if r < 20
    return 1.0 if r <= 60
    return 0.7 if r <= 100
    return 0.4 if r <= 150
    0.2
  end

  def score_pe_level(level)
    return 0.5 if level.nil?
    case level.to_i
    when 2 then 1.0
    when 3 then 0.85
    when 4 then 0.60
    when 5 then 0.40
    when 6 then 0.20
    when 7 then 0.05
    when 1 then 0.10
    else 0.5
    end
  end

  def score_pb_level(level)
    return 0.5 if level.nil?
    case level.to_i
    when 1 then 1.0
    when 2 then 0.85
    when 3 then 0.60
    when 4 then 0.40
    when 5 then 0.20
    when 6 then 0.05
    else 0.5
    end
  end

  def score_peg_level(level)
    return 0.5 if level.nil?
    case level.to_i
    when 1 then 1.0
    when 2 then 0.85
    when 3 then 0.60
    when 4 then 0.30
    when 5 then 0.10
    else 0.5
    end
  end

  def score_asset_liability_ratio(value)
    return 0.5 if value.nil?
    r = value.to_f
    return 0.5 unless r.finite?
    return 1.0 if r <= 0
    return 0.0 if r >= 80.0
    clamp01(1.0 - (r / 80.0))
  end

  def score_fcf_yield(value)
    return 0.5 if value.nil?
    y = value.to_f
    return 0.5 unless y.finite?
    clamp01(y / 10.0)
  end

  def score_roe_level(level)
    return 0.5 if level.nil?
    case level.to_i
    when 1 then 0.40
    when 2 then 0.70
    when 3 then 1.00
    else 0.5
    end
  end

  def score_price_position(value)
    return 0.5 if value.nil?
    p = value.to_f
    return 0.5 unless p.finite?
    clamp01(1.0 - p)
  end

  def clamp01(x)
    clamp(x.to_f, 0.0, 1.0)
  end

  def clamp(x, lo, hi)
    v = x.to_f
    return lo unless v.finite?
    return lo if v < lo
    return hi if v > hi
    v
  end
end
