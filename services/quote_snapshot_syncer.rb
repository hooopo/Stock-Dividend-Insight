require 'faraday'
require 'faraday/retry'
require 'json'

class QuoteSnapshotSyncer
  def initialize(
    scope: Stock.all,
    auto_tune: true,
    batch_sleep: nil,
    jitter: 0.05,
    tune_low: 0.0,
    tune_high: 0.6,
    tune_sample_batches: 6,
    tune_max_fail_rate: 0.05,
    tune_iterations: 5,
    batch_size: 50
  )
    @scope = scope
    @auto_tune = auto_tune
    @batch_sleep = batch_sleep
    @jitter = jitter
    @tune_low = tune_low
    @tune_high = tune_high
    @tune_sample_batches = tune_sample_batches
    @tune_max_fail_rate = tune_max_fail_rate
    @tune_iterations = tune_iterations
    @batch_size = batch_size
  end

  def sync
    sleep_seconds =
      if @batch_sleep
        @batch_sleep
      elsif @auto_tune
        tune_batch_sleep
      else
        0.12
      end

    stocks = []
    @scope.find_each { |s| stocks << s }

    symbols = stocks.map { |s| market_prefix(s.market_id) + s.code.to_s }.uniq

    ok_batches = 0
    fail_batches = 0
    updated = 0
    errors = 0

    symbol_to_stock = stocks.index_by { |s| market_prefix(s.market_id) + s.code.to_s }

    symbols.each_slice(@batch_size).with_index(1) do |batch, idx|
      payload, error = fetch_tencent_batch(symbols: batch, max_attempts: 4, base_backoff: 0.6)

      if error
        fail_batches += 1
        errors += 1
        puts "Quote snapshot batch error (batch=#{idx} size=#{batch.size}): #{error.class}: #{error.message}"
        sleep(sleep_seconds + rand(0.0..@jitter))
        next
      end

      ok_batches += 1
      parse_tencent_lines(payload).each do |symbol, fields|
        stock = symbol_to_stock[symbol]
        next unless stock

        price = parse_float(fields[3])
        volume = parse_int(fields[6])
        amount_wan = parse_float(fields[37])
        turnover_rate = parse_float(fields[38])
        raw_pe_ttm = fields[39]
        pe_ttm = parse_float(raw_pe_ttm)
        float_mv_yi = parse_float(fields[44])
        total_mv_yi = parse_float(fields[45])
        raw_pb = fields[46]
        pb = parse_float(raw_pb)

        stock.current_price = price if price
        stock.volume = volume if volume

        if volume && volume > 0 && amount_wan && amount_wan > 0
          amount_yuan = amount_wan * 10_000.0
          stock.avg_price = amount_yuan / (volume * 100.0)
        end

        stock.turnover_rate = turnover_rate if turnover_rate

        if total_mv_yi && total_mv_yi > 0
          stock.market_cap = total_mv_yi * 100_000_000.0
        end

        if price && price > 0 && total_mv_yi && total_mv_yi > 0
          total_shares = (total_mv_yi * 100_000_000.0 / price)
          stock.total_shares = total_shares.to_i if total_shares.finite?
        end

        pe_missing = raw_pe_ttm.nil? || raw_pe_ttm.to_s.strip.empty? || (pe_ttm && pe_ttm <= 0)
        pb_missing = raw_pb.nil? || raw_pb.to_s.strip.empty? || (pb && pb <= 0)

        if pe_missing
          stock.pe_ttm = nil if stock.pe_ttm.nil? || stock.pe_ttm.to_f <= 0
        else
          stock.pe_ttm = pe_ttm if pe_ttm
        end

        if pb_missing
          stock.pb = nil if stock.pb.nil? || stock.pb.to_f <= 0
        else
          stock.pb = pb if pb
        end

        update_fcf_metrics(stock)

        if stock.changed?
          stock.save!
          updated += 1
        end
      end

      sleep(sleep_seconds + rand(0.0..@jitter))
    end

    puts "Quote snapshot done: sleep=#{sleep_seconds}s batches_ok=#{ok_batches} batches_fail=#{fail_batches} updated=#{updated} errors=#{errors}"
  end

  private
  def update_fcf_metrics(stock)
    market_cap = stock.market_cap.to_f
    unless market_cap.finite? && market_cap > 0
      stock.fcf_yield = nil
      stock.fcf_ev = nil
      return
    end

    if stock.fcff_back.nil?
      stock.fcf_yield = nil
      stock.fcf_ev = nil
      return
    end
    fcf = stock.fcff_back.to_f
    return unless fcf.finite?

    stock.fcf_yield = (fcf / market_cap) * 100.0

    total_liabilities = stock.total_liabilities.to_f
    interest_debt_ratio = stock.interest_debt_ratio.to_f
    if total_liabilities.finite? && total_liabilities > 0 && interest_debt_ratio.finite? && interest_debt_ratio >= 0
      interest_debt_amount = (interest_debt_ratio / 100.0) * total_liabilities
      ev = market_cap + interest_debt_amount
      stock.fcf_ev = ev > 0 ? (fcf / ev) * 100.0 : nil
    else
      stock.fcf_ev = nil
    end
  end

  def tune_batch_sleep
    low = @tune_low
    high = @tune_high

    best = high
    begin
      @tune_iterations.times do |i|
        mid = ((low + high) / 2.0).round(3)
        ok = 0
        fail = 0

        sample_symbols = []
        @scope.order(:id).limit(@tune_sample_batches * @batch_size).find_each do |s|
          sample_symbols << market_prefix(s.market_id) + s.code.to_s
        end
        sample_symbols = sample_symbols.uniq.first(@tune_sample_batches * @batch_size)

        sample_symbols.each_slice(@batch_size).with_index(1) do |batch, idx|
          _payload, error = fetch_tencent_batch(symbols: batch, max_attempts: 2, base_backoff: 0.2)
          if error
            fail += 1
            puts "Quote snapshot tune error (sleep=#{mid}s batch=#{idx}): #{error.class}: #{error.message}"
          else
            ok += 1
          end
          sleep(mid + rand(0.0..@jitter))
        end

        total = ok + fail
        fail_rate = total > 0 ? (fail.to_f / total) : 1.0

        puts "Quote snapshot tune ##{i + 1}/#{@tune_iterations}: sleep=#{mid}s total=#{total} ok=#{ok} fail=#{fail} fail_rate=#{fail_rate.round(4)}"

        if fail_rate <= @tune_max_fail_rate
          best = mid
          high = mid
        else
          low = mid
        end
      end
    rescue Interrupt
      puts "Quote snapshot tune interrupted, using best=#{best}s"
    end

    puts "Quote snapshot tuned sleep=#{best}s"
    best
  end

  def fetch_tencent_batch(symbols:, max_attempts:, base_backoff:)
    last_error = nil
    max_attempts.times do |attempt|
      begin
        response = Faraday.get('https://qt.gtimg.cn/q=' + symbols.join(','), {}, {
          'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer' => 'https://gu.qq.com/',
          'Connection' => 'close'
        }) do |req|
          req.options.timeout = 6
          req.options.open_timeout = 3
        end

        return [nil, StandardError.new("HTTP #{response.status}")] unless response.success?
        body = response.body.to_s
        return [nil, StandardError.new('empty_body')] if body.strip.empty?

        return [body, nil]
      rescue Faraday::SSLError, Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::Error => e
        last_error = e
        sleep(base_backoff * (attempt + 1) + rand(0.0..base_backoff))
        next
      end
    end

    [nil, last_error]
  end

  def parse_tencent_lines(payload)
    lines = payload.lines
    lines.each_with_object({}) do |line, acc|
      next unless (m = line.match(/\Av_(?<symbol>(?:sz|sh)\d{6})=\"(?<data>.*)\";?\s*\z/))
      symbol = m[:symbol]
      data = m[:data]
      acc[symbol] = data.split('~')
    end
  end

  def market_prefix(market_id)
    market_id.to_i == 1 ? 'sh' : 'sz'
  end

  def parse_float(value)
    return nil if value.nil?
    f = value.to_f
    f.finite? ? f : nil
  end

  def parse_int(value)
    return nil if value.nil?
    i = value.to_i
    i >= 0 ? i : nil
  end
end
