require 'date'
require 'faraday'
require 'bigdecimal/util'
require 'json'

class TreasuryYieldSyncer
  def initialize(
    series_id: '2c9081e50a2f9606010a3068cae70001',
    country: 'CN',
    tenor: '10Y',
    source: 'CHINABOND',
    force: false,
    start_date: nil,
    end_date: nil,
    backfill_years: 10,
    chunk_days: 180
  )
    @series_id = series_id
    @country = country
    @tenor = tenor
    @source = source
    @force = force
    @start_date = start_date
    @end_date = end_date
    @backfill_years = backfill_years
    @chunk_days = chunk_days
  end

  def sync
    case @source
    when 'CHINABOND'
      sync_chinabond
    when 'FRED'
      sync_fred
    else
      raise "Unsupported source: #{@source}"
    end
  end

  private

  def sync_chinabond
    end_date = @end_date || Date.today

    last_date =
      if @force
        nil
      else
        TreasuryYield.where(country: @country, tenor: @tenor).maximum(:date)
      end

    start_date =
      @start_date ||
        if last_date
          last_date + 1
        else
          end_date - (@backfill_years * 365)
        end

    if start_date > end_date
      puts "Treasury yield sync: source=#{@source} country=#{@country} tenor=#{@tenor} up_to_date"
      return
    end

    idx10 = nil
    current = start_date
    inserted = 0
    updated = 0
    skipped = 0

    while current <= end_date
      local_chunk_days = @chunk_days
      rows = []
      chunk_end = nil

      loop do
        chunk_end = [current + local_chunk_days, end_date].min
        begin
          rows, idx10 = fetch_chinabond_10y_range(start_date: current, end_date: chunk_end, idx10: idx10)
          break
        rescue Faraday::Error, JSON::ParserError, StandardError => e
          puts "Treasury yield sync error: #{e.class}: #{e.message} range=#{current}..#{chunk_end}"
          if local_chunk_days > 15
            local_chunk_days = (local_chunk_days / 2.0).floor
            next
          end
          rows = []
          break
        end
      end

      if rows.empty?
        current = chunk_end + 1
        next
      end

      now = Time.now
      rows.each do |r|
        r[:country] = @country
        r[:tenor] = @tenor
        r[:series_id] = @series_id.to_s
        r[:source] = @source
        r[:created_at] = now
        r[:updated_at] = now
      end

      begin
        TreasuryYield.upsert_all(rows, unique_by: %i[country tenor date])
      rescue NoMethodError
        rows.each do |r|
          rec = TreasuryYield.find_or_initialize_by(country: r[:country], tenor: r[:tenor], date: r[:date])
          rec.series_id = r[:series_id]
          rec.source = r[:source]
          rec.yield_pct = r[:yield_pct]
          if rec.new_record?
            rec.save!
            inserted += 1
          elsif rec.changed?
            rec.save!
            updated += 1
          else
            skipped += 1
          end
        end
      else
        inserted += rows.size
      end

      current = chunk_end + 1
    end

    latest = TreasuryYield.where(country: @country, tenor: @tenor).order(date: :desc).first
    puts "Treasury yield sync: source=#{@source} country=#{@country} tenor=#{@tenor} start=#{start_date} end=#{end_date} latest=#{latest&.date} inserted≈#{inserted} updated=#{updated} skipped=#{skipped}"
  end

  def fetch_chinabond_10y_range(start_date:, end_date:, idx10:)
    conn = Faraday.new(url: 'https://yield.chinabond.com.cn') do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    params = {
      startTime: start_date.to_s,
      endTime: end_date.to_s,
      qxlx: '0,',
      yqqxN: 'N',
      yqqxK: 'K',
      ycDefIds: @series_id.to_s,
      locale: 'zh_CN'
    }
    url = '/cbweb-mn/yc/queryXyz?' + URI.encode_www_form(params)

    response = nil
    retries = 3
    begin
      response = conn.post(url, '', {
        'User-Agent' => 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer' => 'https://yield.chinabond.com.cn/cbweb-mn/yield_main',
        'Content-Type' => 'application/x-www-form-urlencoded',
        'Connection' => 'close'
      }) do |req|
        req.options.timeout = 30
        req.options.open_timeout = 8
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError, Faraday::Error => e
      retries -= 1
      if retries >= 0
        sleep((4 - retries) * 1.2 + rand(0.0..0.8))
        retry
      end
      raise e
    end

    raise "CHINABOND HTTP #{response.status}" unless response.success?

    parsed = JSON.parse(response.body) rescue nil
    raise 'CHINABOND invalid_json' unless parsed.is_a?(Array)

    rows = []
    parsed.each do |day|
      next unless day.is_a?(Hash)

      date = Date.parse(day['workTime'].to_s) rescue nil
      next unless date

      bzqx = day['bzqx']
      syl = day['syl']
      next unless bzqx.is_a?(Array) && syl.is_a?(Array) && bzqx.size == syl.size

      idx10 ||= bzqx.find_index { |x| x.to_f == 10.0 }
      next unless idx10

      raw = syl[idx10]
      next if raw.nil? || raw.to_s.strip.empty? || raw.to_s.strip == '.'

      yield_pct = raw.to_d
      next unless yield_pct.finite?

      rows << { date: date, yield_pct: yield_pct }
    end

    [rows, idx10]
  end

  def sync_fred
    require 'csv'

    url = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=#{@series_id}"
    response = Faraday.get(url) do |req|
      req.options.timeout = 15
      req.options.open_timeout = 8
    end
    raise "FRED HTTP #{response.status}" unless response.success?

    last_date =
      if @force
        nil
      else
        TreasuryYield.where(country: @country, tenor: @tenor).maximum(:date)
      end

    inserted = 0
    updated = 0
    skipped = 0

    CSV.parse(response.body, headers: true).each do |row|
      date = Date.parse(row['observation_date']) rescue nil
      next unless date

      if last_date && date <= last_date
        skipped += 1
        next
      end

      raw = row[@series_id]
      next if raw.nil? || raw.strip.empty? || raw.strip == '.'

      yield_pct = raw.to_d

      rec = TreasuryYield.find_or_initialize_by(country: @country, tenor: @tenor, date: date)
      rec.series_id = @series_id
      rec.source = @source
      rec.yield_pct = yield_pct

      if rec.new_record?
        rec.save!
        inserted += 1
      elsif rec.changed?
        rec.save!
        updated += 1
      else
        skipped += 1
      end
    end

    puts "Treasury yield sync: source=#{@source} series=#{@series_id} inserted=#{inserted} updated=#{updated} skipped=#{skipped}"
  end
end
