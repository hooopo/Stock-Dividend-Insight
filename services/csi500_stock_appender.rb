require 'faraday'
require 'json'
require 'yaml'

class Csi500StockAppender
  def initialize(file_path: 'stocks-pro.yml')
    @file_path = file_path
  end

  def run
    existing_data = YAML.load_file(@file_path)
    list = existing_data.is_a?(Hash) ? (existing_data['stocks'] || []) : (existing_data || [])
    list, dedupe_report = dedupe_by_code(list)
    existing_codes = list.map { |x| x['code'].to_s.rjust(6, '0') }.to_h { |c| [c, true] }
    puts "stocks_deduped=#{dedupe_report[:deduped]}" if dedupe_report[:deduped] > 0
    changed = dedupe_report[:deduped] > 0

    constituents = fetch_sina_csi500_constituents
    puts "csi500_total=#{constituents.size}"

    missing = constituents.reject { |x| existing_codes[x[:code]] }
    puts "csi500_missing=#{missing.size}"

    prepared = []
    skipped_st = []
    skipped_delist = []
    skipped_mismatch = []
    skipped_unresolved = []
    renamed = []

    tencent_names = fetch_tencent_names(missing.map { |x| to_tencent_symbol(x[:code]) }.uniq)

    conn = Faraday.new do |f|
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end
    url_em = 'https://searchapi.eastmoney.com/api/suggest/get'

    missing.each do |row|
      code = row[:code]
      sina_name = row[:name]

      em = em_lookup(conn, url_em, code)
      unless em
        skipped_unresolved << [code, sina_name, 'eastmoney_not_found']
        next
      end

      em_name = em['Name'].to_s.strip
      if st_or_delist?(em_name)
        skipped_st << [code, em_name]
        next
      end

      tencent_name = tencent_names[to_tencent_symbol(code)]
      if tencent_name.nil? || tencent_name.strip.empty?
        skipped_delist << [code, em_name, 'tencent_empty']
        next
      end

      if st_or_delist?(tencent_name)
        skipped_st << [code, tencent_name]
        next
      end

      if names_consistent?(tencent_name, em_name)
        renamed << [code, sina_name, em_name] unless names_consistent?(sina_name, em_name)
      else
        skipped_mismatch << [code, sina_name, em_name, tencent_name]
        next
      end

      prepared << { 'code' => code, 'name' => em_name, 'categories' => [] }
    end

    prepared.each { |x| existing_codes[x['code']] = true }
    prepared = prepared.uniq { |x| x['code'] }.reject { |x| list.any? { |e| e['code'].to_s.rjust(6, '0') == x['code'] } }

    puts "csi500_add=#{prepared.size}"
    puts "csi500_skip_st=#{skipped_st.size}"
    puts "csi500_skip_delist=#{skipped_delist.size}"
    puts "csi500_skip_mismatch=#{skipped_mismatch.size}"
    puts "csi500_skip_unresolved=#{skipped_unresolved.size}"
    puts "csi500_renamed=#{renamed.size}"

    skipped_st.first(30).each { |x| puts "skip_st\t#{x[0]}\t#{x[1]}" }
    skipped_delist.first(30).each { |x| puts "skip_delist\t#{x[0]}\t#{x[1]}\t#{x[2]}" }
    skipped_mismatch.first(30).each { |x| puts "skip_mismatch\t#{x[0]}\t#{x[1]}\t#{x[2]}\t#{x[3]}" }
    skipped_unresolved.first(30).each { |x| puts "skip_unresolved\t#{x[0]}\t#{x[1]}\t#{x[2]}" }
    renamed.first(30).each { |x| puts "renamed\t#{x[0]}\t#{x[1]}\t#{x[2]}" }

    if !prepared.empty?
      list.concat(prepared)
      changed = true
    end

    list, dedupe_report_after = dedupe_by_code(list)
    changed ||= dedupe_report_after[:deduped] > 0
    puts "stocks_deduped_after_add=#{dedupe_report_after[:deduped]}" if dedupe_report_after[:deduped] > 0

    return unless changed

    out =
      if existing_data.is_a?(Hash)
        existing_data['stocks'] = list
        existing_data.to_yaml
      else
        list.to_yaml
      end

    out = out.gsub(/^(\s*-\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    out = out.gsub(/^(\s*code:\s*)'?(\d{6})'?\s*$/, '\\1"\\2"')
    File.write(@file_path, out)

    puts "csi500_written=#{prepared.size} file=#{@file_path}"
  end

  private

  def fetch_sina_csi500_constituents
    rows = []
    page = 1
    loop do
      url = "https://vip.stock.finance.sina.com.cn/corp/go.php/vII_NewestComponent/indexid/000905.phtml?page=#{page}"
      resp = Faraday.get(url, {}, { 'User-Agent' => 'Mozilla/5.0' }) do |req|
        req.options.timeout = 15
        req.options.open_timeout = 8
      end
      break unless resp.success?

      html = resp.body.to_s
      html = html.force_encoding('GBK').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      page_rows = html.scan(%r{<tr[^>]*>\s*<td><div align="center">(?<code>\d{6})</div></td>\s*<td><div align="center"><a[^>]*>(?<name>[^<]+)</a>}m)
      break if page_rows.empty?

      page_rows.each do |code, name|
        code = code.to_s.strip.rjust(6, '0')
        name = name.to_s.strip
        next unless code.match?(/^\d{6}$/)
        rows << { code: code, name: name }
      end

      page += 1
      break if page > 40
      sleep(0.08 + rand(0.0..0.12))
    end

    rows.uniq { |x| x[:code] }
  end

  def em_lookup(conn, url_em, code)
    rows = em_suggest_rows(conn, url_em, code)
    return nil if rows.nil? || rows.empty?

    expected_quoteid = (code.start_with?('6') ? '1.' : '0.') + code
    exact = rows.find { |x| x['Code'].to_s == code && x['QuoteID'].to_s == expected_quoteid }
    return exact if exact

    by_code = rows.find { |x| x['Code'].to_s == code }
    by_code
  end

  def em_suggest_rows(conn, url_em, input)
    response = conn.get(url_em, { input: input, type: 14, count: 10 }, { 'User-Agent' => 'Mozilla/5.0' }) do |req|
      req.options.timeout = 8
      req.options.open_timeout = 5
    end
    return nil unless response.status == 200

    parsed = JSON.parse(response.body) rescue nil
    rows = parsed && parsed.dig('QuotationCodeTable', 'Data')
    return nil unless rows && !rows.empty?

    rows.select do |x|
      x['Code'].to_s.match?(/^\d{6}$/) &&
        x['QuoteID'].to_s.match?(/^[01]\.\d{6}$/) &&
        x['SecurityTypeName'].to_s.match?(/沪A|深A|科创|创业/)
    end
  rescue Faraday::Error
    nil
  end

  def fetch_tencent_names(symbols)
    return {} if symbols.empty?

    out = {}
    symbols.each_slice(50).with_index(1) do |batch, idx|
      payload = nil
      last_error = nil

      3.times do |attempt|
        begin
          resp = Faraday.get('https://qt.gtimg.cn/q=' + batch.join(','), {}, {
            'User-Agent' => 'Mozilla/5.0',
            'Referer' => 'https://gu.qq.com/',
            'Connection' => 'close'
          }) do |req|
            req.options.timeout = 10
            req.options.open_timeout = 5
          end
          raise "HTTP #{resp.status}" unless resp.success?
          payload = resp.body.to_s
          payload = payload.force_encoding('GBK').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
          break
        rescue Faraday::Error, StandardError => e
          last_error = e
          sleep(0.4 * (attempt + 1) + rand(0.0..0.3))
        end
      end

      if payload.nil?
        puts "tencent_batch_error batch=#{idx} size=#{batch.size} error=#{last_error.class}: #{last_error.message}"
        next
      end

      parse_tencent_lines(payload).each do |symbol, fields|
        name = to_utf8(fields[1]).strip
        out[symbol] = name unless name.empty?
      end

      sleep(0.05 + rand(0.0..0.08))
    end

    out
  end

  def parse_tencent_lines(payload)
    payload.lines.each_with_object({}) do |line, acc|
      m = line.match(/\Av_(?<symbol>(?:sz|sh)\d{6})=\"(?<data>.*)\";?\s*\z/)
      next unless m
      acc[m[:symbol]] = m[:data].split('~')
    end
  end

  def to_tencent_symbol(code)
    (code.start_with?('6') ? 'sh' : 'sz') + code
  end

  def st_or_delist?(name)
    n = to_utf8(name).strip
    return true if n.empty?
    return true if n.include?('退市')
    return true if n.match?(/\A\*?ST/i)
    return true if n.match?(/\APT/i)
    false
  end

  def normalize_name(name)
    s = to_utf8(name)
    s = s.unicode_normalize(:nfkc) if s.respond_to?(:unicode_normalize)
    s.strip.gsub(/\s+/, '').gsub(/[·•\*]/, '').upcase
  end

  def names_consistent?(a, b)
    na = normalize_name(a)
    nb = normalize_name(b)
    return true if na == nb
    return true if na.include?(nb) || nb.include?(na)
    false
  end

  def dedupe_by_code(list)
    seen = {}
    deduped = 0
    merged = []

    list.each do |row|
      code = row['code'].to_s.rjust(6, '0')
      if seen.key?(code)
        deduped += 1
        base = seen[code]
        base['categories'] ||= []
        row_categories = row['categories'] || []
        base['categories'] = (base['categories'] + row_categories).map(&:to_s).uniq
        base['name'] = row['name'] if base['name'].to_s.strip.empty? && !row['name'].to_s.strip.empty?
        next
      end

      normalized = row.dup
      normalized['code'] = code
      normalized['categories'] = (normalized['categories'] || []).map(&:to_s)
      seen[code] = normalized
      merged << normalized
    end

    [merged, { deduped: deduped }]
  end


  def to_utf8(value)
    s = value.to_s
    return s if s.encoding == Encoding::UTF_8
    if s.encoding == Encoding::ASCII_8BIT
      return s.dup.force_encoding('GBK').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end

    s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    s.dup.force_encoding('GBK').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  end
end
