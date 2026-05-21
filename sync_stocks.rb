require 'active_record'
require 'date'
require 'dotenv/load'
require 'yaml'
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
require_relative 'services/boshi_hldw100_constituents_appender'
require_relative 'services/macro_metric_syncer'
require_relative 'services/future_dividend_syncer'

class StockSyncService
  def initialize(incremental: false, force: false, force_pull: false, backfill_cn10y: false, add_csi500: false, add_a500: false, add_kc50: false, add_tech50: false, add_ai50: false, add_dividend_etf_constituents: false, add_boshi_hldw100: false, add_fcf: false, add_theme_etf_constituents: false, backfill_fcf: false, skip_second_pass: false, fill_categories: false, sync_valuation_history: true, valuation_years: 10, valuation_force: false, sync_roe_history: true, roe_years: 12, gt3: false, optimize_gt3_yml: false, gt3_min_market_cap_yi: 200.0)
    @incremental = incremental
    @force = force
    @force_pull = force_pull
    @backfill_cn10y = backfill_cn10y
    @gt3 = gt3
    @optimize_gt3_yml = optimize_gt3_yml
    @gt3_min_market_cap_yi = gt3_min_market_cap_yi.to_f
    @add_csi500 = add_csi500
    @add_a500 = add_a500
    @add_kc50 = add_kc50
    @add_tech50 = add_tech50
    @add_ai50 = add_ai50
    @add_dividend_etf_constituents = add_dividend_etf_constituents
    @add_boshi_hldw100 = add_boshi_hldw100
    @add_fcf = add_fcf
    @add_theme_etf_constituents = add_theme_etf_constituents
    @backfill_fcf = backfill_fcf
    @skip_second_pass = skip_second_pass
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
    if @optimize_gt3_yml
      prune_gt3_yml_by_market_cap!(min_market_cap_yi: @gt3_min_market_cap_yi)
      return
    end

    if @add_theme_etf_constituents
      apply_theme_etf_constituents_to_yml!
      return
    end

    if @gt3
      @add_csi500 = false
      @add_a500 = false
      @add_kc50 = false
      @add_tech50 = false
      @add_ai50 = false
      @add_dividend_etf_constituents = false
      @add_boshi_hldw100 = false
      @add_fcf = false
      @add_theme_etf_constituents = false
      @fill_categories = false
    end

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
    if @add_boshi_hldw100
      BoshiHldw100ConstituentsAppender.new(file_path: 'stocks-pro.yml').run
    end
    if @add_fcf
      FcfIndexConstituentsAppender.new(file_path: 'stocks-pro.yml', index_id: '980092').run
    end
    if @fill_categories || @add_csi500 || @add_a500 || @add_kc50 || @add_tech50 || @add_ai50 || @add_dividend_etf_constituents || @add_boshi_hldw100 || @add_fcf
      CategoryBackfiller.new(file_path: 'stocks-pro.yml').run
    end

    # 1. 加载股票列表
    loader_file = @gt3 ? 'stocks-dividend-gt3.yml' : 'stocks-pro.yml'
    StockLoader.new(loader_file).load

    codes =
      begin
        data = YAML.load_file(loader_file)
        list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])
        list
          .map { |x| x['code'].to_s.strip.rjust(6, '0') }
          .select { |x| x.match?(/^\d{6}$/) }
          .uniq
      rescue StandardError
        []
      end

    stock_scope =
      if @gt3 && codes.any?
        Stock.where(asset_type: 'stock', code: codes)
      else
        Stock.where(asset_type: 'stock')
      end
    quote_scope =
      if @gt3 && codes.any?
        Stock.where(asset_type: 'stock', code: codes)
      else
        Stock.where(asset_type: %w[stock etf index])
      end
    
    # 1.5 同步十年期国债收益率
    TreasuryYieldSyncer.new(country: 'CN', tenor: '10Y', source: 'CHINABOND', force: @backfill_cn10y).sync

    # 2. 同步实时快照（换手率、市值、量、均价、PE/PB、总股本等）
    QuoteSnapshotSyncer.new(scope: quote_scope).sync
    if !@skip_second_pass
      need_quote_scope =
        quote_scope
          .where(current_price: nil)
          .or(Stock.where(market_cap: nil))
          .or(Stock.where(total_shares: nil))
      QuoteSnapshotSyncer.new(scope: need_quote_scope, auto_tune: false, batch_sleep: 0.15).sync if need_quote_scope.exists?
    end
    
    begin
      MacroMetricSyncer.new.sync
    rescue StandardError
    end

    need_fin_scope =
      stock_scope
        .where(finance_report_date: nil)
        .or(Stock.where('finance_report_date < ?', Date.today - 365))
        .or(Stock.where(peg_level: nil))
        .or(Stock.where(asset_liability_ratio: nil))
        .or(Stock.where(fcff_back: nil))
    FinanceSnapshotSyncer.new(scope: need_fin_scope, sleep_range: (0.04..0.10)).sync if need_fin_scope.exists?
    if !@skip_second_pass
      remaining_fin_scope =
        stock_scope
          .where(finance_report_date: nil)
          .or(Stock.where('finance_report_date < ?', Date.today - 365))
          .or(Stock.where(peg_level: nil))
          .or(Stock.where(asset_liability_ratio: nil))
          .or(Stock.where(fcff_back: nil))
      FinanceSnapshotSyncer.new(scope: remaining_fin_scope, sleep_range: (0.12..0.24)).sync if remaining_fin_scope.exists?
    end
    if @backfill_fcf
      puts({ fcff_nil: Stock.where(fcff_back: nil).count, fcf_yield_nil: Stock.where(fcf_yield: nil).count, fcf_ev_nil: Stock.where(fcf_ev: nil).count }.inspect)
      puts "FCF backfill completed successfully."
      return
    end

    if @sync_roe_history
      need_roe_scope =
        stock_scope
          .where(roe_report_date: nil)
          .or(Stock.where('roe_report_date < ?', Date.today - 365))
          .or(Stock.where(roe_5y_std: nil))
          .or(Stock.where(roe_trend_score: nil))
      RoeHistorySyncer.new(scope: need_roe_scope, years: @roe_years, sleep_range: (0.04..0.10)).sync if need_roe_scope.exists?
      if !@skip_second_pass
        remaining_roe_scope =
          stock_scope
            .where(roe_report_date: nil)
            .or(Stock.where('roe_report_date < ?', Date.today - 365))
            .or(Stock.where(roe_5y_std: nil))
            .or(Stock.where(roe_trend_score: nil))
        RoeHistorySyncer.new(scope: remaining_roe_scope, years: @roe_years, sleep_range: (0.12..0.24)).sync if remaining_roe_scope.exists?
      end
    end
    
    # 3. 同步 K 线
    PriceHistorySyncer.new(incremental: @incremental && !@force_pull, force: @force || @force_pull, scope: stock_scope).sync
    stock_scope.where(drop_30d: nil).find_each { |s| PriceMetricsCalculator.calculate(s) }

    if @sync_valuation_history
      need_val_scope =
        stock_scope
          .left_joins(:price_histories)
          .where(
            '((price_histories.date >= :d AND (price_histories.pb IS NULL OR price_histories.pe_ttm IS NULL)) OR (stocks.pe_ttm > 0 AND stocks.pe_percentile IS NULL) OR (stocks.pb > 0 AND stocks.pb_percentile IS NULL))',
            d: Date.today - 365
          )
          .distinct
      ValuationHistorySyncer.new(scope: need_val_scope, years: @valuation_years, force: @valuation_force, sleep_range: (0.04..0.10)).sync if need_val_scope.exists?
      if !@skip_second_pass
        remaining_val_scope =
          stock_scope
            .left_joins(:price_histories)
            .where(
              '((price_histories.date >= :d AND (price_histories.pb IS NULL OR price_histories.pe_ttm IS NULL)) OR (stocks.pe_ttm > 0 AND stocks.pe_percentile IS NULL) OR (stocks.pb > 0 AND stocks.pb_percentile IS NULL))',
              d: Date.today - 365
            )
            .distinct
        ValuationHistorySyncer.new(scope: remaining_val_scope, years: @valuation_years, force: @valuation_force, sleep_range: (0.12..0.24)).sync if remaining_val_scope.exists?
      end
    end
    
    # 4. 同步分红数据
    DividendSyncer.new(force: @force_pull, scope: stock_scope).sync

    FutureDividendSyncer.new(days_back: 30, days_ahead: 3650).sync
    
    # 5. 量化计算及打标
    ValuationCalculator.new.calculate_all
    
    puts({
      finance_report_date_nil: Stock.where(finance_report_date: nil).count,
      asset_liability_ratio_nil: Stock.where(asset_liability_ratio: nil).count,
      fcff_back_nil: Stock.where(fcff_back: nil).count,
      pe_percentile_missing: Stock.where('pe_ttm > 0').where(pe_percentile: nil).count,
      pb_percentile_missing: Stock.where('pb > 0').where(pb_percentile: nil).count,
      roe_report_date_nil: Stock.where(roe_report_date: nil).count
    }.inspect)
    puts "Stock synchronization and valuation calculation completed successfully."
  end

  private

  def prune_gt3_yml_by_market_cap!(file_path: 'stocks-dividend-gt3.yml', min_market_cap_yi: 200.0)
    raise "missing #{file_path}" unless File.exist?(file_path)

    data = YAML.load_file(file_path)
    list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])

    rows =
      list.filter_map do |row|
        code = row.is_a?(Hash) ? row['code'].to_s.strip.rjust(6, '0') : nil
        next unless code&.match?(/^\d{6}$/)
        row.merge('code' => code)
      end

    codes = rows.map { |r| r['code'] }.uniq
    scope = Stock.where(asset_type: 'stock', code: codes)
    cap_by_code = scope.pluck(:code, :market_cap).to_h
    threshold_yuan = min_market_cap_yi.to_f * 100_000_000.0

    below = 0
    nil_cap = 0
    not_found = 0
    kept =
      rows.select do |r|
        code = r['code']
        cap = cap_by_code[code]
        if !cap_by_code.key?(code)
          not_found += 1
          true
        elsif cap.nil? || cap.to_f <= 0
          nil_cap += 1
          true
        elsif cap.to_f < threshold_yuan
          below += 1
          false
        else
          true
        end
      end

    kept_codes = kept.map { |r| r['code'] }.to_h { |c| [c, true] }
    new_list =
      list.filter_map do |row|
        next row unless row.is_a?(Hash)
        code = row['code'].to_s.strip.rjust(6, '0')
        next unless code.match?(/^\d{6}$/)
        next unless kept_codes[code]
        row.merge('code' => code)
      end

    out =
      if data.is_a?(Hash)
        data['stocks'] = new_list
        data.to_yaml
      else
        new_list.to_yaml
      end

    out = out.gsub(/^(\s*-\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    out = out.gsub(/^(\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    File.write(file_path, out)

    puts "gt3_yml_pruned file=#{file_path} min_market_cap_yi=#{min_market_cap_yi} before=#{rows.size} kept=#{kept.size} removed_below=#{below} kept_nil_market_cap=#{nil_cap} kept_not_found=#{not_found}"
  end

  def apply_theme_etf_constituents_to_yml!
    file_path = 'stocks-pro.yml'
    index_ids = %w[
      930601
      931594
      931719
      h30597
      980141
      000928
      930721
    ]

    index_ids.each do |index_id|
      Csi500StockAppender.new(file_path: file_path, index_id: index_id.to_s, metric_prefix: "theme_#{index_id}").run
    end

    CategoryBackfiller.new(file_path: file_path).run
    remove_etf_constituent_labels_from_yml!(file_path)
    puts "theme_etf_constituents_done file=#{file_path}"
  end

  def remove_etf_constituent_labels_from_yml!(file_path)
    data = YAML.load_file(file_path)
    list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])

    list.each do |row|
      cats = (row['categories'] || []).map(&:to_s)
      cats = cats.reject { |c| c.end_with?('ETF成分股') }.uniq
      row['categories'] = cats
    end

    out =
      if data.is_a?(Hash)
        data['stocks'] = list
        data.to_yaml
      else
        list.to_yaml
      end

    out = out.gsub(/^(\s*-\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    out = out.gsub(/^(\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    File.write(file_path, out)
  end
end

if __FILE__ == $0
  incremental = ARGV.include?('--incremental')
  force = ARGV.include?('--force')
  force_pull = ARGV.include?('--force-pull')
  backfill_cn10y = ARGV.include?('--backfill-cn10y')
  gt3 = ARGV.include?('--gt3')
  optimize_gt3_yml = ARGV.include?('--optimize-gt3-yml')
  gt3_min_market_cap_yi = (ARGV.find { |x| x.start_with?('--gt3-min-market-cap-yi=') } || '').split('=', 2)[1].to_f
  gt3_min_market_cap_yi = 200.0 if gt3_min_market_cap_yi <= 0
  add_csi500 = ARGV.include?('--add-csi500')
  add_a500 = ARGV.include?('--add-a500')
  add_kc50 = ARGV.include?('--add-kc50')
  add_tech50 = ARGV.include?('--add-tech50')
  add_ai50 = ARGV.include?('--add-ai50')
  add_dividend_etf_constituents = ARGV.include?('--add-dividend-etf-constituents')
  add_boshi_hldw100 = ARGV.include?('--add-boshi-hldw100')
  add_fcf = ARGV.include?('--add-fcf')
  add_theme_etf_constituents = ARGV.include?('--add-theme-etf-constituents')
  backfill_fcf = ARGV.include?('--backfill-fcf')
  skip_second_pass = ARGV.include?('--skip-second-pass')
  fill_categories = ARGV.include?('--fill-categories')
  sync_valuation_history = !ARGV.include?('--skip-valuation-history')
  valuation_years = (ARGV.find { |x| x.start_with?('--valuation-years=') } || '').split('=', 2)[1].to_i
  valuation_years = 10 if valuation_years <= 0
  valuation_force = ARGV.include?('--valuation-force')
  sync_roe_history = !ARGV.include?('--skip-roe-history')
  roe_years = (ARGV.find { |x| x.start_with?('--roe-years=') } || '').split('=', 2)[1].to_i
  roe_years = 12 if roe_years <= 0
  StockSyncService.new(incremental: incremental, force: force, force_pull: force_pull, backfill_cn10y: backfill_cn10y, gt3: gt3, optimize_gt3_yml: optimize_gt3_yml, gt3_min_market_cap_yi: gt3_min_market_cap_yi, add_csi500: add_csi500, add_a500: add_a500, add_kc50: add_kc50, add_tech50: add_tech50, add_ai50: add_ai50, add_dividend_etf_constituents: add_dividend_etf_constituents, add_boshi_hldw100: add_boshi_hldw100, add_fcf: add_fcf, add_theme_etf_constituents: add_theme_etf_constituents, backfill_fcf: backfill_fcf, skip_second_pass: skip_second_pass, fill_categories: fill_categories, sync_valuation_history: sync_valuation_history, valuation_years: valuation_years, valuation_force: valuation_force, sync_roe_history: sync_roe_history, roe_years: roe_years).run
end
