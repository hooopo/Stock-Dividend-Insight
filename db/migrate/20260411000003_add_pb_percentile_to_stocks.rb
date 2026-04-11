class AddPbPercentileToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :pb_percentile, :decimal, precision: 6, scale: 4
    add_column :stocks, :pb_percentile_level, :integer
    add_index :stocks, :pb_percentile_level
  end
end

