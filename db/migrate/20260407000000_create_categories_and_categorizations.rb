class CreateCategoriesAndCategorizations < ActiveRecord::Migration[7.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :categories, :name, unique: true

    create_table :categorizations do |t|
      t.references :stock, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.timestamps
    end
    add_index :categorizations, [:stock_id, :category_id], unique: true
  end
end
