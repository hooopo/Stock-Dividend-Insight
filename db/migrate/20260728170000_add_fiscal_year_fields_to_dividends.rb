class AddFiscalYearFieldsToDividends < ActiveRecord::Migration[8.1]
  def change
    add_column :dividends, :ex_dividend_date, :date unless column_exists?(:dividends, :ex_dividend_date)
    add_column :dividends, :fiscal_year, :integer unless column_exists?(:dividends, :fiscal_year)

    add_index :dividends, :ex_dividend_date unless index_exists?(:dividends, :ex_dividend_date)
    add_index :dividends, :fiscal_year unless index_exists?(:dividends, :fiscal_year)
    add_index :dividends, [:stock_id, :fiscal_year], name: 'index_dividends_on_stock_id_and_fiscal_year' unless index_exists?(:dividends, [:stock_id, :fiscal_year], name: 'index_dividends_on_stock_id_and_fiscal_year')
  end
end
