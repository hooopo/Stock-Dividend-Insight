class AddAssetTypeToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :asset_type, :string, null: false, default: 'stock' unless column_exists?(:stocks, :asset_type)
    add_index :stocks, :asset_type unless index_exists?(:stocks, :asset_type)
  end
end
