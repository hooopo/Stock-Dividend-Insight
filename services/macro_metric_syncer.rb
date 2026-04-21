require 'date'
require 'faraday'
require 'digest'
require 'json'
require 'time'

class MacroMetricSyncer
  URL = 'https://qieman.com/pmdj/v2/idx-eval/latest'.freeze

  def sync
    now = Time.now
    json = fetch_json(URL)
    as_of_at = parse_ms_time(json['date']) || now
    list = Array(json['idxEvalList'])

    upserted = 0
    skipped = 0

    list.each do |row|
      index_code = row['indexCode'].to_s.strip
      next if index_code.empty?

      eval_at = parse_ms_time(row['date']) || as_of_at
      eval_date = eval_at.to_date

      pe = row['pe']
      pe_percentile = row['pePercentile']
      pe_high = row['peHigh']
      pe_low = row['peLow']

      pb = row['pb']
      pb_percentile = row['pbPercentile']
      pb_high = row['pbHigh']
      pb_low = row['pbLow']

      rec = {
        index_code: index_code,
        index_name: row['indexName']&.to_s,
        eval_date: eval_date,
        as_of_at: as_of_at,
        pe: pe.nil? ? nil : pe.to_f,
        pe_percentile: pe_percentile.nil? ? nil : pe_percentile.to_f,
        pe_high: pe_high.nil? ? nil : pe_high.to_f,
        pe_low: pe_low.nil? ? nil : pe_low.to_f,
        pb: pb.nil? ? nil : pb.to_f,
        pb_percentile: pb_percentile.nil? ? nil : pb_percentile.to_f,
        pb_high: pb_high.nil? ? nil : pb_high.to_f,
        pb_low: pb_low.nil? ? nil : pb_low.to_f,
        roe: row['roe'].nil? ? nil : row['roe'].to_f,
        group: row['group']&.to_s,
        source: row['source'],
        score_by: row['scoreBy'],
        category: Array(row['category']).map { |x| x.to_s }.reject(&:empty?),
        fund_codes: Array(row['fundCodes']).map { |x| x.to_s }.reject(&:empty?),
        all_fund_codes: Array(row['allFundCodes']).map { |x| x.to_s }.reject(&:empty?),
        raw_json: row,
        created_at: now,
        updated_at: now
      }

      QiemanIndexEval.upsert(rec, unique_by: %i[index_code eval_date])
      upserted += 1
    rescue StandardError
      skipped += 1
      next
    end

    { qieman_idx_eval: { upserted: upserted, skipped: skipped, source: URL, as_of_at: as_of_at } }
  end

  private

  def fetch_json(url)
    ms = (Time.now.to_f * 1000).to_i
    sign = ms.to_s + Digest::SHA256.hexdigest((ms * 1.01).floor.to_s).upcase[0, 32]

    resp = Faraday.get(url, {}, {
      'Accept' => 'application/json',
      'User-Agent' => 'Mozilla/5.0',
      'Cache-Control' => 'no-store',
      'x-sign' => sign,
      'Connection' => 'close'
    }) do |req|
      req.options.timeout = 15
      req.options.open_timeout = 8
    end
    raise "http #{resp.status}" unless resp.success?
    JSON.parse(resp.body.to_s)
  end

  def parse_ms_time(ms)
    return nil if ms.nil?
    v = ms.to_i
    return nil if v <= 0
    Time.at(v / 1000.0)
  rescue StandardError
    nil
  end
end
