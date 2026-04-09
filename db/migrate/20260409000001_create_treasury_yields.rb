class CreateTreasuryYields < ActiveRecord::Migration[8.1]
  def change
    create_table :treasury_yields do |t|
      t.date :date, null: false
      t.string :country, null: false
      t.string :tenor, null: false
      t.string :series_id, null: false
      t.decimal :yield_pct, precision: 10, scale: 4, null: false
      t.string :source, null: false
      t.timestamps null: false
    end

    add_index :treasury_yields, [:country, :tenor, :date], unique: true
  end
end
