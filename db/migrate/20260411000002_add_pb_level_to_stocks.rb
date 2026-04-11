class AddPbLevelToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :pb_level, :integer
    add_index :stocks, :pb_level
  end
end

