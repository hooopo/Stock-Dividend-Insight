require 'active_record'
require 'dotenv/load'
require_relative 'models'
require_relative 'services/stock_loader'
require_relative 'services/price_history_syncer'
require_relative 'services/price_metrics_calculator'
require_relative 'services/dividend_syncer'
require_relative 'services/valuation_calculator'

class StockSyncService
  def initialize(incremental: false, force: false)
    @incremental = incremental
    @force = force
  end

  def run
    # 1. 加载股票列表
    StockLoader.new.load
    
    # 2. 同步 K 线
    PriceHistorySyncer.new(incremental: @incremental, force: @force).sync
    
    # 3. 同步分红数据
    DividendSyncer.new.sync
    
    # 4. 量化计算及打标
    ValuationCalculator.new.calculate_all
    
    puts "Stock synchronization and valuation calculation completed successfully."
  end
end

if __FILE__ == $0
  incremental = ARGV.include?('--incremental')
  force = ARGV.include?('--force')
  StockSyncService.new(incremental: incremental, force: force).run
end
