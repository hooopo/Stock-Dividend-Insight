class PriceHistoryCleaner
  def initialize(dry_run: false)
    @dry_run = dry_run
  end

  def orphan_count
    PriceHistory.where('stock_id IS NULL OR NOT EXISTS (SELECT 1 FROM stocks WHERE stocks.id = price_histories.stock_id)').count
  end

  def delete_orphans
    return 0 if @dry_run
    ActiveRecord::Base.connection.delete('DELETE FROM price_histories WHERE stock_id IS NULL OR NOT EXISTS (SELECT 1 FROM stocks WHERE stocks.id = price_histories.stock_id)')
  end
end

