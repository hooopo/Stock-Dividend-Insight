class AddDividendPayoutRatioToStocksAndSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :dividend_payout_ratio, :decimal, precision: 10, scale: 4 unless column_exists?(:stocks, :dividend_payout_ratio)
    add_index :stocks, :dividend_payout_ratio unless index_exists?(:stocks, :dividend_payout_ratio)

    add_column :pool_snapshot_items, :dividend_payout_ratio, :decimal, precision: 10, scale: 4 unless column_exists?(:pool_snapshot_items, :dividend_payout_ratio)
    add_index :pool_snapshot_items, :dividend_payout_ratio unless index_exists?(:pool_snapshot_items, :dividend_payout_ratio)
  end
end

