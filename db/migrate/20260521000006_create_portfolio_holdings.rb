class CreatePortfolioHoldings < ActiveRecord::Migration[8.1]
  def change
    create_table :portfolio_holdings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :stock, null: false, foreign_key: true
      t.bigint :shares, null: false
      t.decimal :avg_cost, precision: 12, scale: 4, null: false
      t.date :bought_on
      t.timestamps
    end

    add_index :portfolio_holdings, [:user_id, :stock_id], unique: true
  end
end
