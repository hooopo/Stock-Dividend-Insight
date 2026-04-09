require 'active_record'
require 'dotenv/load'
require_relative 'models'
require_relative 'services/stock_loader'
require_relative 'services/price_history_syncer'
require_relative 'services/price_metrics_calculator'
require_relative 'services/quote_snapshot_syncer'
require_relative 'services/treasury_yield_syncer'
require_relative 'services/csi500_stock_appender'
require_relative 'services/category_backfiller'
require_relative 'services/dividend_etf_constituents_appender'
require_relative 'services/dividend_syncer'
require_relative 'services/valuation_calculator'

class StockSyncService
  def initialize(incremental: false, force: false, force_pull: false, backfill_cn10y: false, add_csi500: false, add_a500: false, add_dividend_etf_constituents: false, fill_categories: false)
    @incremental = incremental
    @force = force
    @force_pull = force_pull
    @backfill_cn10y = backfill_cn10y
    @add_csi500 = add_csi500
    @add_a500 = add_a500
    @add_dividend_etf_constituents = add_dividend_etf_constituents
    @fill_categories = fill_categories
  end

  def run
    if @add_csi500
      Csi500StockAppender.new(file_path: 'stocks-pro.yml', index_id: '000905', metric_prefix: 'csi500').run
    end
    if @add_a500
      Csi500StockAppender.new(file_path: 'stocks-pro.yml', index_id: '000510', metric_prefix: 'a500').run
    end
    if @add_dividend_etf_constituents
      DividendEtfConstituentsAppender.new(file_path: 'stocks-pro.yml', index_ids: ['000015']).run
    end
    if @fill_categories || @add_csi500 || @add_a500 || @add_dividend_etf_constituents
      CategoryBackfiller.new(file_path: 'stocks-pro.yml').run
    end

    # 1. 加载股票列表
    StockLoader.new.load
    
    # 1.5 同步十年期国债收益率
    TreasuryYieldSyncer.new(country: 'CN', tenor: '10Y', source: 'CHINABOND', force: @backfill_cn10y).sync

    # 2. 同步实时快照（换手率、市值、量、均价、PE/PB、总股本等）
    QuoteSnapshotSyncer.new.sync
    
    # 3. 同步 K 线
    PriceHistorySyncer.new(incremental: @incremental && !@force_pull, force: @force || @force_pull).sync
    
    # 4. 同步分红数据
    DividendSyncer.new(force: @force_pull).sync
    
    # 5. 量化计算及打标
    ValuationCalculator.new.calculate_all
    
    puts "Stock synchronization and valuation calculation completed successfully."
  end
end

if __FILE__ == $0
  incremental = ARGV.include?('--incremental')
  force = ARGV.include?('--force')
  force_pull = ARGV.include?('--force-pull')
  backfill_cn10y = ARGV.include?('--backfill-cn10y')
  add_csi500 = ARGV.include?('--add-csi500')
  fill_categories = ARGV.include?('--fill-categories')
  add_a500 = ARGV.include?('--add-a500')
  add_dividend_etf_constituents = ARGV.include?('--add-dividend-etf-constituents')
  StockSyncService.new(incremental: incremental, force: force, force_pull: force_pull, backfill_cn10y: backfill_cn10y, add_csi500: add_csi500, add_a500: add_a500, add_dividend_etf_constituents: add_dividend_etf_constituents, fill_categories: fill_categories).run
end
