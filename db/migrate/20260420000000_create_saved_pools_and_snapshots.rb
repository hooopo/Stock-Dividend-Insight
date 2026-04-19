class CreateSavedPoolsAndSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :saved_pools do |t|
      t.bigint :user_id, null: false
      t.string :name, null: false
      t.text :query_string, null: false
      t.timestamps
    end

    add_index :saved_pools, :user_id unless index_exists?(:saved_pools, :user_id)
    add_index :saved_pools, %i[user_id name] unless index_exists?(:saved_pools, %i[user_id name])

    create_table :pool_snapshots do |t|
      t.bigint :saved_pool_id, null: false
      t.datetime :taken_at, null: false
      t.integer :total_count, null: false, default: 0
      t.timestamps
    end

    add_index :pool_snapshots, :saved_pool_id unless index_exists?(:pool_snapshots, :saved_pool_id)
    add_index :pool_snapshots, %i[saved_pool_id taken_at] unless index_exists?(:pool_snapshots, %i[saved_pool_id taken_at])

    create_table :pool_snapshot_items do |t|
      t.bigint :pool_snapshot_id, null: false
      t.bigint :stock_id, null: false
      t.string :code
      t.string :name

      t.decimal :current_price, precision: 15, scale: 4
      t.decimal :dividend_yield, precision: 10, scale: 4
      t.decimal :expected_dividend_yield, precision: 10, scale: 4
      t.decimal :pe_ttm, precision: 10, scale: 2
      t.decimal :pb, precision: 10, scale: 2
      t.decimal :peg, precision: 10, scale: 4
      t.decimal :roe_jq, precision: 10, scale: 4
      t.decimal :asset_liability_ratio, precision: 10, scale: 4
      t.decimal :interest_debt_ratio, precision: 10, scale: 4
      t.decimal :fcf_yield, precision: 10, scale: 4
      t.decimal :fcf_ev, precision: 10, scale: 4
      t.decimal :pe_percentile, precision: 5, scale: 4
      t.decimal :pb_percentile, precision: 5, scale: 4
      t.decimal :price_position, precision: 5, scale: 4
      t.decimal :pos_30d, precision: 5, scale: 4
      t.decimal :drop_30d, precision: 10, scale: 4
      t.decimal :market_cap, precision: 20, scale: 2
      t.decimal :turnover_rate, precision: 10, scale: 4
      t.bigint :volume

      t.timestamps
    end

    add_index :pool_snapshot_items, :pool_snapshot_id unless index_exists?(:pool_snapshot_items, :pool_snapshot_id)
    add_index :pool_snapshot_items, :stock_id unless index_exists?(:pool_snapshot_items, :stock_id)
    add_index :pool_snapshot_items, %i[pool_snapshot_id stock_id], unique: true unless index_exists?(:pool_snapshot_items, %i[pool_snapshot_id stock_id])
  end
end
