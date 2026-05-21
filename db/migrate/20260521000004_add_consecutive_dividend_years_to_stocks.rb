class AddConsecutiveDividendYearsToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :consecutive_dividend_years, :integer unless column_exists?(:stocks, :consecutive_dividend_years)
    add_index :stocks, :consecutive_dividend_years unless index_exists?(:stocks, :consecutive_dividend_years)
  end
end
