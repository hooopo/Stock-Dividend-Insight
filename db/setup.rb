require 'active_record'
require 'yaml'

ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  database: 'stock_dividend_insight'
)

class CreateStocks < ActiveRecord::Migration[8.1]
  def change
    create_table :stocks do |t|
      t.string :name, null: false
      t.string :secid, null: false
      t.string :code, null: false
      t.integer :market_id, null: false
      t.timestamps
    end
    add_index :stocks, :secid, unique: true
    add_index :stocks, :code

    create_table :price_histories do |t|
      t.references :stock, null: false, foreign_key: true
      t.date :date, null: false
      t.decimal :open, precision: 15, scale: 4
      t.decimal :close, precision: 15, scale: 4
      t.decimal :high, precision: 15, scale: 4
      t.decimal :low, precision: 15, scale: 4
      t.bigint :volume
      t.decimal :amount, precision: 20, scale: 4
      t.decimal :amplitude, precision: 10, scale: 4
      t.timestamps
    end
    add_index :price_histories, [:stock_id, :date], unique: true
  end
end

if __FILE__ == $0
  begin
    CreateStocks.migrate(:up)
    puts "Migrations ran successfully."
  rescue => e
    puts "Migrations failed: #{e.message}"
  end
end
