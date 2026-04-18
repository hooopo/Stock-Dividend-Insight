require 'active_record'
require 'date'
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
require_relative 'services/finance_snapshot_syncer'
require_relative 'services/fcf_index_constituents_appender'

class StockSyncService
  def initialize(incremental: false, force: false, force_pull: false, backfill_cn10y: false, add_csi500: false, add_a500: false, add_kc50: false, add_tech50: false, add_ai50: false, add_dividend_etf_constituents: false, add_fcf: false, fill_categories: false, sync_valuation_history: true, valuation_years: 10, valuation_force: false, sync_roe_history: true, roe_years: 12)
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
    @add_fcf = add_fcf
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
    if @add_fcf
      FcfIndexConstituentsAppender.new(file_path: 'stocks-pro.yml', index_id: '980092').run
    end
    if @fill_categories || @add_csi500 || @add_a500 || @add_kc50 || @add_tech50 || @add_ai50 || @add_dividend_etf_constituents || @add_fcf
      CategoryBackfiller.new(file_path: 'stocks-pro.yml').run
    end

    # 1. 加载股票列表
    StockLoader.new.load
    
    # 1.5 同步十年期国债收益率
    TreasuryYieldSyncer.new(country: 'CN', tenor: '10Y', source: 'CHINABOND', force: @backfill_cn10y).sync

    # 2. 同步实时快照（换手率、市值、量、均价、PE/PB、总股本等）
    QuoteSnapshotSyncer.new.sync

    need_fin_scope =
      Stock
        .where(finance_report_date: nil)
        .or(Stock.where('finance_report_date < ?', Date.today - 365))
        .or(Stock.where(peg_level: nil))
        .or(Stock.where(asset_liability_ratio: nil))
        .or(Stock.where(fcff_back: nil))
    FinanceSnapshotSyncer.new(scope: need_fin_scope, sleep_range: (0.04..0.10)).sync if need_fin_scope.exists?

    if @sync_roe_history
      need_roe_scope =
        Stock
          .where(roe_report_date: nil)
          .or(Stock.where('roe_report_date < ?', Date.today - 365))
      RoeHistorySyncer.new(scope: need_roe_scope, years: @roe_years, sleep_range: (0.04..0.10)).sync if need_roe_scope.exists?
    end
    
    # 3. 同步 K 线
    PriceHistorySyncer.new(incremental: @incremental && !@force_pull, force: @force || @force_pull).sync

    if @sync_valuation_history
      need_val_scope =
        Stock
          .joins(:price_histories)
          .where('price_histories.date >= ?', Date.today - 365)
          .where('price_histories.pb IS NULL OR price_histories.pe_ttm IS NULL')
          .distinct
      need_val_scope =
        need_val_scope
          .or(Stock.where('pe_ttm > 0').where(pe_percentile: nil))
          .or(Stock.where('pb > 0').where(pb_percentile: nil))
      ValuationHistorySyncer.new(scope: need_val_scope, years: @valuation_years, force: @valuation_force, sleep_range: (0.04..0.10)).sync if need_val_scope.exists?
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
  add_a500 = ARGV.include?('--add-a500')
  add_kc50 = ARGV.include?('--add-kc50')
  add_tech50 = ARGV.include?('--add-tech50')
  add_ai50 = ARGV.include?('--add-ai50')
  add_dividend_etf_constituents = ARGV.include?('--add-dividend-etf-constituents')
  add_fcf = ARGV.include?('--add-fcf')
  fill_categories = ARGV.include?('--fill-categories')
  sync_valuation_history = !ARGV.include?('--skip-valuation-history')
  valuation_years = (ARGV.find { |x| x.start_with?('--valuation-years=') } || '').split('=', 2)[1].to_i
  valuation_years = 10 if valuation_years <= 0
  valuation_force = ARGV.include?('--valuation-force')
  sync_roe_history = !ARGV.include?('--skip-roe-history')
  roe_years = (ARGV.find { |x| x.start_with?('--roe-years=') } || '').split('=', 2)[1].to_i
  roe_years = 12 if roe_years <= 0
  StockSyncService.new(incremental: incremental, force: force, force_pull: force_pull, backfill_cn10y: backfill_cn10y, add_csi500: add_csi500, add_a500: add_a500, add_kc50: add_kc50, add_tech50: add_tech50, add_ai50: add_ai50, add_dividend_etf_constituents: add_dividend_etf_constituents, add_fcf: add_fcf, fill_categories: fill_categories, sync_valuation_history: sync_valuation_history, valuation_years: valuation_years, valuation_force: valuation_force, sync_roe_history: sync_roe_history, roe_years: roe_years).run
end
