class AddQuoteSnapshotFieldsToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :turnover_rate, :decimal, precision: 10, scale: 4 unless column_exists?(:stocks, :turnover_rate)
    add_column :stocks, :market_cap, :decimal, precision: 20, scale: 2 unless column_exists?(:stocks, :market_cap)
    add_column :stocks, :volume, :bigint unless column_exists?(:stocks, :volume)
    add_column :stocks, :avg_price, :decimal, precision: 15, scale: 4 unless column_exists?(:stocks, :avg_price)
    add_column :stocks, :pe_ttm, :decimal, precision: 10, scale: 2 unless column_exists?(:stocks, :pe_ttm)
    add_column :stocks, :pb, :decimal, precision: 10, scale: 2 unless column_exists?(:stocks, :pb)
    add_column :stocks, :total_shares, :bigint unless column_exists?(:stocks, :total_shares)
  end
end
