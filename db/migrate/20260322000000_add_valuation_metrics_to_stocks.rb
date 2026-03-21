class AddValuationMetricsToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :price_position, :decimal, precision: 5, scale: 4
    add_column :stocks, :dividend_yield_position, :decimal, precision: 5, scale: 4
    add_column :stocks, :comprehensive_position, :decimal, precision: 5, scale: 4
    add_column :stocks, :valuation_label, :string
    
    # 注释
    # price_position: 当前价格在历史价格区间的百分位 (0-1)
    # dividend_yield_position: 当前股息率在历史股息率区间的百分位 (0-1)
    # comprehensive_position: 综合位置 (基于红利策略: 0.5 * 价格位置 + 0.5 * (1 - 股息率位置))
    # valuation_label: 估值标签 (底部区域, 偏低, 中位, 偏高, 高位区域)
  end
end
