class AddLastSyncedAtToStocks < ActiveRecord::Migration[7.0]
  def change
    add_column :stocks, :last_synced_at, :datetime
  end
end
