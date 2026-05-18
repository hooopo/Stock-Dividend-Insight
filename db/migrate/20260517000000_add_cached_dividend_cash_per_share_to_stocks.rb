class AddCachedDividendCashPerShareToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :dividend_cash_per_share_year, :integer unless column_exists?(:stocks, :dividend_cash_per_share_year)
    add_column :stocks, :dividend_cash_per_share_latest_year, :decimal, precision: 12, scale: 4 unless column_exists?(:stocks, :dividend_cash_per_share_latest_year)

    add_index :stocks, :dividend_cash_per_share_year unless index_exists?(:stocks, :dividend_cash_per_share_year)
    add_index :stocks, :dividend_cash_per_share_latest_year unless index_exists?(:stocks, :dividend_cash_per_share_latest_year)
  end
end
