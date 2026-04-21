class CreateQiemanIndexEvals < ActiveRecord::Migration[8.1]
  def change
    create_table :qieman_index_evals do |t|
      t.string :index_code, null: false
      t.string :index_name
      t.date :eval_date, null: false
      t.datetime :as_of_at

      t.decimal :pe, precision: 12, scale: 4
      t.decimal :pe_percentile, precision: 8, scale: 6
      t.decimal :pe_high, precision: 12, scale: 4
      t.decimal :pe_low, precision: 12, scale: 4

      t.decimal :pb, precision: 12, scale: 4
      t.decimal :pb_percentile, precision: 8, scale: 6
      t.decimal :pb_high, precision: 12, scale: 4
      t.decimal :pb_low, precision: 12, scale: 4

      t.decimal :roe, precision: 12, scale: 6

      t.string :group
      t.integer :source
      t.integer :score_by

      t.text :category, array: true
      t.text :fund_codes, array: true
      t.text :all_fund_codes, array: true

      t.jsonb :raw_json
      t.timestamps
    end

    add_index :qieman_index_evals, %i[index_code eval_date], unique: true
    add_index :qieman_index_evals, :eval_date
  end
end
