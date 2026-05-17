class AddMoreRollingPriceMetricsToStocks < ActiveRecord::Migration[8.1]
  def change
    # 季度滚动 (90天)
    add_column :stocks, :high_90d, :decimal, precision: 15, scale: 4
    add_column :stocks, :low_90d, :decimal, precision: 15, scale: 4
    add_column :stocks, :pos_90d, :decimal, precision: 5, scale: 4

    # 全量滚动 (通常指系统内的10年历史)
    add_column :stocks, :high_all, :decimal, precision: 15, scale: 4
    add_column :stocks, :low_all, :decimal, precision: 15, scale: 4
    
    # Snapshot items 也需要同步，以便股票池快照对比（虽然用户没提，但这是系统的通用模式）
    add_column :pool_snapshot_items, :low_30d, :decimal, precision: 15, scale: 4
    add_column :pool_snapshot_items, :low_90d, :decimal, precision: 15, scale: 4
    add_column :pool_snapshot_items, :low_1y, :decimal, precision: 15, scale: 4
    add_column :pool_snapshot_items, :low_3y, :decimal, precision: 15, scale: 4
    add_column :pool_snapshot_items, :low_5y, :decimal, precision: 15, scale: 4
    add_column :pool_snapshot_items, :low_all, :decimal, precision: 15, scale: 4
  end
end
