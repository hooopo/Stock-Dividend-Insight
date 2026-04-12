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
require_relative 'services/valuation_history_syncer'
require_relative 'services/roe_history_syncer'

class StockSyncService
  def initialize(incremental: false, force: false, force_pull: false, backfill_cn10y: false, add_csi500: false, add_a500: false, add_kc50: false, add_tech50: false, add_ai50: false, add_dividend_etf_constituents: false, fill_categories: false, sync_valuation_history: false, valuation_years: 10, valuation_force: false, sync_roe_history: false, roe_years: 12)
    @incremental = incremental
    @force = force
    @force_pull = force_pull
    @backfill_cn10y = backfill_cn10y
    @add_csi500 = add_csi500
    @add_a500 = add_a500
    @add_kc50 = add_kc50
    @add_tech50 = add_tech50
    @add_ai50 = add_ai50
    @add_dividend_etf_constituents = add_dividend_etf_constituents
    @fill_categories = fill_categories
    @sync_valuation_history = sync_valuation_history
    @valuation_years = valuation_years.to_i
    @valuation_years = 10 if @valuation_years <= 0
    @valuation_force = valuation_force
    @sync_roe_history = sync_roe_history
    @roe_years = roe_years.to_i
    @roe_years = 12 if @roe_years <= 0
  end

  def run
    if @add_csi500
      Csi500StockAppender.new(file_path: 'stocks-pro.yml', index_id: '000905', metric_prefix: 'csi500').run
    end
    if @add_a500
      Csi500StockAppender.new(file_path: 'stocks-pro.yml', index_id: '000510', metric_prefix: 'a500').run
    end
    if @add_kc50
      Csi500StockAppender.new(file_path: 'stocks-pro.yml', index_id: '000688', metric_prefix: 'kc50').run
    end
    if @add_tech50
      Csi500StockAppender.new(file_path: 'stocks-pro.yml', index_id: '399279', metric_prefix: 'tech50').run
    end
    if @add_ai50
      Csi500StockAppender.new(file_path: 'stocks-pro.yml', index_id: '399284', metric_prefix: 'ai50').run
    end
    if @add_dividend_etf_constituents
      DividendEtfConstituentsAppender.new(file_path: 'stocks-pro.yml', index_ids: ['000015']).run
    end
    if @fill_categories || @add_csi500 || @add_a500 || @add_kc50 || @add_tech50 || @add_ai50 || @add_dividend_etf_constituents
      CategoryBackfiller.new(file_path: 'stocks-pro.yml').run
    end

    # 1. 加载股票列表
    StockLoader.new.load
    
    # 1.5 同步十年期国债收益率
    TreasuryYieldSyncer.new(country: 'CN', tenor: '10Y', source: 'CHINABOND', force: @backfill_cn10y).sync

    # 2. 同步实时快照（换手率、市值、量、均价、PE/PB、总股本等）
    QuoteSnapshotSyncer.new.sync

    if @sync_roe_history
      RoeHistorySyncer.new(years: @roe_years, sleep_range: (0.04..0.10)).sync
    end
    
    # 3. 同步 K 线
    PriceHistorySyncer.new(incremental: @incremental && !@force_pull, force: @force || @force_pull).sync

    if @sync_valuation_history
      ValuationHistorySyncer.new(years: @valuation_years, force: @valuation_force, sleep_range: (0.04..0.10)).sync
    end
    
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
  add_kc50 = ARGV.include?('--add-kc50')
  add_tech50 = ARGV.include?('--add-tech50')
  add_ai50 = ARGV.include?('--add-ai50')
  add_dividend_etf_constituents = ARGV.include?('--add-dividend-etf-constituents')
  sync_valuation_history = ARGV.include?('--sync-valuation-history')
  valuation_years = (ARGV.find { |x| x.start_with?('--valuation-years=') } || '').split('=', 2)[1].to_i
  valuation_years = 10 if valuation_years <= 0
  valuation_force = ARGV.include?('--valuation-force')
  sync_roe_history = ARGV.include?('--sync-roe-history')
  roe_years = (ARGV.find { |x| x.start_with?('--roe-years=') } || '').split('=', 2)[1].to_i
  roe_years = 12 if roe_years <= 0
  StockSyncService.new(incremental: incremental, force: force, force_pull: force_pull, backfill_cn10y: backfill_cn10y, add_csi500: add_csi500, add_a500: add_a500, add_kc50: add_kc50, add_tech50: add_tech50, add_ai50: add_ai50, add_dividend_etf_constituents: add_dividend_etf_constituents, fill_categories: fill_categories, sync_valuation_history: sync_valuation_history, valuation_years: valuation_years, valuation_force: valuation_force, sync_roe_history: sync_roe_history, roe_years: roe_years).run
end
