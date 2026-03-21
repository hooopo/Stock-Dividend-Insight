class AddPePbToStocksAndPriceHistories < ActiveRecord::Migration[8.1]
  def change
    # 为 stocks 表添加字段
    add_column :stocks, :pe, :decimal, precision: 10, scale: 4        # 当前市盈率 (PE TTM/动态)
    add_column :stocks, :pb, :decimal, precision: 10, scale: 4        # 当前市净率 (PB)
    add_column :stocks, :pe_position, :decimal, precision: 5, scale: 4 # PE 历史百分位
    add_column :stocks, :pb_position, :decimal, precision: 5, scale: 4 # PB 历史百分位
    
    # 为 price_histories 表添加字段，用于存储历史估值
    add_column :price_histories, :pe, :decimal, precision: 10, scale: 4 # 历史市盈率
    add_column :price_histories, :pb, :decimal, precision: 10, scale: 4 # 历史市净率
  end
end
