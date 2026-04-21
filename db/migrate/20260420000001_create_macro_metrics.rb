class CreateMacroMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :macro_metrics do |t|
      t.string :code, null: false
      t.date :date, null: false
      t.decimal :value, precision: 10, scale: 4
      t.timestamps
    end

    add_index :macro_metrics, %i[code date], unique: true unless index_exists?(:macro_metrics, %i[code date])
    add_index :macro_metrics, :code unless index_exists?(:macro_metrics, :code)
    add_index :macro_metrics, :date unless index_exists?(:macro_metrics, :date)
  end
end
