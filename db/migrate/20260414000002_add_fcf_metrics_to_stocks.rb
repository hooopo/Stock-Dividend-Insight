class AddFcfMetricsToStocks < ActiveRecord::Migration[8.1]
  def change
    add_column :stocks, :fcff_back, :decimal, precision: 20, scale: 4
    add_column :stocks, :fcf_yield, :decimal, precision: 10, scale: 4
    add_column :stocks, :fcf_ev, :decimal, precision: 10, scale: 4

    add_index :stocks, :fcf_yield unless index_exists?(:stocks, :fcf_yield)
    add_index :stocks, :fcf_ev unless index_exists?(:stocks, :fcf_ev)
  end
end
