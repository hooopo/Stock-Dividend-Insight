class AddRoeTrendScoreToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :roe_trend_score, :decimal, precision: 10, scale: 4
    add_index :stocks, :roe_trend_score
  end
end
