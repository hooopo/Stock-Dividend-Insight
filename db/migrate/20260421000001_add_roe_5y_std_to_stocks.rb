class AddRoe5yStdToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :roe_5y_std, :decimal, precision: 10, scale: 4
    add_index :stocks, :roe_5y_std
  end
end
