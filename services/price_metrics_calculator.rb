class PriceMetricsCalculator
  def self.calculate(stock)
    # 获取数据库中最新的价格记录作为基准日期和收盘价
    latest_history = stock.price_histories.order(date: :desc).first
    return if latest_history.nil?

    base_price = stock.current_price && stock.current_price.to_f > 0 ? stock.current_price.to_f : latest_history.close
    base_date = latest_history.date

    # 1. 30天滚动 (月度)
    update_metrics(stock, "30d", 30, base_date, base_price)

    # 2. 1年滚动 (年度)
    update_metrics(stock, "1y", 365, base_date, base_price)

    # 3. 3年滚动
    update_metrics(stock, "3y", 1095, base_date, base_price)

    # 4. 5年滚动
    update_metrics(stock, "5y", 1825, base_date, base_price)

    stock.save! if stock.changed?
  end

  private

  def self.update_metrics(stock, suffix, days, base_date, base_price)
    start_date = base_date - days
    scope = stock.price_histories.where('date >= ? AND date <= ?', start_date, base_date)
    
    high = scope.maximum(:high)
    low = scope.minimum(:low)

    if high && low
      stock.send("high_#{suffix}=", high)
      stock.send("low_#{suffix}=", low)

      if high > low
        pos = (base_price - low) / (high - low)
        stock.send("pos_#{suffix}=", [[pos.to_f, 0.0].max, 1.0].min)
      else
        stock.send("pos_#{suffix}=", 0.5)
      end
    end
  end
end
