require 'faraday'
require 'yaml'

class CategoryBackfiller
  BROAD_CATEGORIES = %w[
    金融
    消费
    工业
    信息技术
    医药卫生
    公用事业
    能源
    原材料
    电信业务
    交通运输
    房地产
    传媒
    农业
  ].freeze

  STOP_BOARDS = %w[
    中盘
    大盘
    小盘
    次新股
    融资融券
    转融券
    深股通
    沪股通
    专精特新
  ].freeze

  MANUAL_BY_CODE = {
    '001221' => %w[家居用品 可选消费],
    '301536' => %w[半导体 信息技术],
    '301498' => %w[食品加工 消费],
    '688475' => %w[软件开发 信息技术],
    '600535' => %w[中药 医药卫生],
    '603786' => %w[汽车零部件 可选消费],
    '002595' => %w[专用设备 工业],
    '002203' => %w[有色金属 原材料],
    '603379' => %w[化学制品 原材料],
    '002797' => %w[证券 金融],
    '601118' => %w[化学制品 原材料],
    '601106' => %w[专用设备 工业],
    '000623' => %w[中药 医药卫生],
    '603650' => %w[化学制品 原材料],
    '002831' => %w[印刷包装机械 工业],
    '601179' => %w[电网设备 工业],
    '000009' => %w[电池 工业],
    '600598' => %w[农业 农业],
    '600126' => %w[钢铁 原材料],
    '601016' => %w[新能源发电 公用事业],
    '601168' => %w[有色金属 原材料],
    '600392' => %w[有色金属 原材料],
    '600380' => %w[化学制药 医药卫生],
    '002444' => %w[专用设备 工业],
    '002078' => %w[造纸 原材料],
    '600141' => %w[化学制品 原材料],
    '600673' => %w[化学制品 原材料],
    '000997' => %w[软件开发 信息技术],
    '002056' => %w[光伏设备 工业],
    '000830' => %w[化学制品 原材料],
    '000683' => %w[化学制品 原材料],
    '300390' => %w[电池 工业],
    '000785' => %w[零售 可选消费],
    '000987' => %w[金融],
    '600208' => %w[房地产开发 房地产],
    '002683' => %w[专用设备 工业],
    '000629' => %w[有色金属 原材料],
    '600348' => %w[煤炭 能源],
    '000021' => %w[计算机设备 信息技术],
    '603077' => %w[化学制品 原材料],
    '002891' => %w[饲料 消费],
    '300083' => %w[专用设备 工业],
    '000415' => %w[多元金融 金融],
    '688608' => %w[半导体 信息技术],
    '000426' => %w[有色金属 原材料],
    '605589' => %w[化学制品 原材料],
    '600864' => %w[多元金融 金融],
    '000032' => %w[计算机设备 信息技术],
    '300442' => %w[软件开发 信息技术],
    '001965' => %w[高速公路 交通运输],
    '002318' => %w[钢铁 原材料],
    '000998' => %w[农业 农业],
    '000988' => %w[光学光电子 信息技术],
    '000977' => %w[计算机设备 信息技术],
    '000661' => %w[生物制品 医药卫生],
    '000063' => %w[通信设备 信息技术],
    '001979' => %w[房地产开发 房地产],
    '001914' => %w[房地产开发 房地产],
    '000999' => %w[中药 医药卫生],
    '002292' => %w[传媒],
    '002371' => %w[半导体 信息技术],
    '002405' => %w[软件开发 信息技术],
    '002407' => %w[化学制品 原材料],
    '002414' => %w[光学光电子 信息技术],
    '002463' => %w[电子元件 信息技术],
    '002472' => %w[汽车零部件 可选消费],
    '002497' => %w[化学制品 原材料],
    '002517' => %w[传媒],
    '002544' => %w[通信设备 信息技术],
    '300088' => %w[光学光电子 信息技术],
    '300118' => %w[光伏设备 工业],
    '300457' => %w[专用设备 工业],
    '300568' => %w[电池 工业],
    '301236' => %w[软件开发 信息技术],
    '600026' => %w[航运港口 交通运输],
    '600039' => %w[建筑装饰 工业],
    '600667' => %w[半导体 信息技术],
    '600839' => %w[白色家电 可选消费],
    '600895' => %w[房地产开发 房地产],
    '600941' => %w[通信服务 电信业务],
    '603392' => %w[生物制品 医药卫生],
    '605117' => %w[光伏设备 工业],
    '688072' => %w[半导体 信息技术],
    '688390' => %w[光伏设备 工业],
    '600123' => %w[煤炭 能源],
    '600997' => %w[煤炭 能源],
    '601339' => %w[纺织服饰 可选消费],
    '600755' => %w[供应链服务 交通运输],
    '600350' => %w[高速公路 交通运输]
  }.freeze

  def initialize(file_path: 'stocks-pro.yml', stocks_yml_path: 'stocks.yml', sleep_range: (0.05..0.12), use_sina: true)
    @file_path = file_path
    @stocks_yml_path = stocks_yml_path
    @sleep_range = sleep_range
    @use_sina = use_sina
    @sina_blocked = false
  end

  def run
    data = YAML.load_file(@file_path)
    list = data.is_a?(Hash) ? (data['stocks'] || []) : (data || [])

    industry_to_broad = build_industry_to_broad_map(list)
    known_subcategories = build_known_subcategories(list)
    name_to_broad = parse_stocks_yml_sections(@stocks_yml_path)

    empty = list.select { |x| (x['categories'] || []).empty? }
    puts "category_empty_before=#{empty.size}"
    return if empty.empty?

    conn =
      if @use_sina
        Faraday.new(url: 'https://vip.stock.finance.sina.com.cn') do |f|
          f.request :url_encoded
          f.adapter Faraday.default_adapter
        end
      end

    filled = 0
    unresolved = 0

    empty.each do |row|
      code = row['code'].to_s.rjust(6, '0')
      name = row['name'].to_s

      manual = MANUAL_BY_CODE[code]
      if manual
        row['categories'] = manual
        filled += 1
        next
      end

      categories = nil

      if @use_sina && !@sina_blocked
        industry = fetch_sina_industry(conn, code)
        if industry && !industry.empty?
          broad = industry_to_broad[industry] || broad_guess(industry)
          categories = [industry]
          categories << broad if broad && broad != industry
        else
          categories = infer_from_boards(conn, code, known_subcategories, industry_to_broad)
        end
      end

      categories ||= infer_from_local(name_to_broad, name, industry_to_broad)

      if categories.nil? || categories.empty?
        unresolved += 1
        next
      end

      row['categories'] = categories.uniq
      filled += 1

      sleep(rand(@sleep_range)) if @sleep_range
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
    File.write(@file_path, out)

    remain = (YAML.load_file(@file_path)['stocks'] || []).count { |x| (x['categories'] || []).empty? }
    puts "category_filled=#{filled} unresolved=#{unresolved} category_empty_after=#{remain}"
  end

  private
  def parse_stocks_yml_sections(path)
    return {} unless path && File.exist?(path)

    broad = nil
    out = {}

    File.read(path, encoding: 'UTF-8').each_line do |line|
      line = line.strip
      next if line.empty?

      if (m = line.match(/\A#\s*=====\s*(.+?)\s*=====/))
        broad = broad_from_section_title(m[1])
        next
      end

      if (m = line.match(/\A-\s*name:\s*(.+)\z/))
        name = m[1].to_s.strip
        out[name] = broad if broad && !name.empty?
      end
    end

    out
  end

  def broad_from_section_title(title)
    t = title.to_s
    return '金融' if t.include?('银行') || t.include?('证券') || t.include?('保险')
    return '能源' if t.include?('能源') || t.include?('煤炭') || t.include?('石油') || t.include?('天然气')
    return '公用事业' if t.include?('电力') || t.include?('公用事业') || t.include?('燃气')
    return '交通运输' if t.include?('交通运输') || t.include?('航空') || t.include?('铁路') || t.include?('港口') || t.include?('航运')
    return '工业' if t.include?('基建') || t.include?('机械') || t.include?('军工') || t.include?('制造')
    return '原材料' if t.include?('钢铁') || t.include?('建材') || t.include?('有色') || t.include?('化工')
    return '医药卫生' if t.include?('医药')
    return '信息技术' if t.include?('科技') || t.include?('半导体') || t.include?('计算机')
    return '可选消费' if t.include?('消费') || t.include?('汽车') || t.include?('家电')
    return '房地产' if t.include?('房地产')
    return '传媒' if t.include?('传媒')
    nil
  end

  def build_known_subcategories(list)
    set = {}
    list.each do |row|
      (row['categories'] || []).each do |c|
        c = c.to_s
        next if c.empty?
        next if BROAD_CATEGORIES.include?(c)
        set[c] = true
      end
    end
    set
  end

  def build_industry_to_broad_map(list)
    counts = Hash.new { |h, k| h[k] = Hash.new(0) }

    list.each do |row|
      cats = (row['categories'] || []).map(&:to_s).uniq
      broad = (cats & BROAD_CATEGORIES).first
      next unless broad

      cats.each do |c|
        next if BROAD_CATEGORIES.include?(c)
        counts[c][broad] += 1
      end
    end

    counts.to_h do |industry, by_broad|
      best = by_broad.max_by { |_k, v| v }&.first
      [industry, best]
    end
  end

  def fetch_sina_industry(conn, code)
    path = "/corp/go.php/vCI_CorpOtherInfo/stockid/#{code}/menu_num/2.phtml"

    retries = 3
    begin
      resp = conn.get(path, {}, { 'User-Agent' => 'Mozilla/5.0', 'Connection' => 'close' }) do |req|
        req.options.timeout = 15
        req.options.open_timeout = 8
      end
      if resp.status.to_i == 456
        @sina_blocked = true
        return nil
      end
      return nil unless resp.success?

      html = resp.body.to_s
      html = html.force_encoding('GBK').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      m = html.match(%r{<td class="ct" align="center">([^<]+)</td>\s*<td class="ct" align="center"><a[^>]+Type=}m)
      industry = m && m[1].to_s.strip
      industry
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError, Faraday::Error
      retries -= 1
      if retries >= 0
        sleep(0.6 + rand(0.0..0.8))
        retry
      end
      nil
    end
  end

  def infer_from_boards(conn, code, known_subcategories, industry_to_broad)
    return nil if @sina_blocked
    boards = fetch_sina_boards(conn, code)
    return nil if boards.empty?

    boards.each do |b|
      next if STOP_BOARDS.include?(b)
      if known_subcategories[b]
        broad = industry_to_broad[b] || broad_guess(b)
        categories = [b]
        categories << broad if broad && broad != b
        return categories.uniq
      end
    end

    boards.each do |b|
      next if STOP_BOARDS.include?(b)
      categories = infer_by_keyword(b)
      next if categories.nil? || categories.empty?
      return categories.uniq
    end

    nil
  end

  def fetch_sina_boards(conn, code)
    path = "/corp/go.php/vCI_CorpOtherInfo/stockid/#{code}/menu_num/5.phtml"

    retries = 3
    begin
      resp = conn.get(path, {}, { 'User-Agent' => 'Mozilla/5.0', 'Connection' => 'close' }) do |req|
        req.options.timeout = 15
        req.options.open_timeout = 8
      end
      if resp.status.to_i == 456
        @sina_blocked = true
        return []
      end
      return [] unless resp.success?

      html = resp.body.to_s
      html = html.force_encoding('GBK').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')

      boards = html.scan(/<td class="ct" align="center">([^<]{2,30})<\/td>\s*<td class="ct" align="center"><a[^>]+mkt\/#/).flatten
      boards.map(&:strip).reject(&:empty?).uniq
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError, Faraday::Error
      retries -= 1
      if retries >= 0
        sleep(0.6 + rand(0.0..0.8))
        retry
      end
      []
    end
  end

  def infer_from_local(name_to_broad, name, industry_to_broad)
    broad = name_to_broad[name] || broad_guess(name)
    industry = nil

    n = name.to_s
    if n.include?('证券')
      industry = '证券'
      broad ||= '金融'
    elsif n.include?('银行')
      industry = '银行'
      broad ||= '金融'
    elsif n.include?('机场')
      industry = '机场'
      broad ||= '交通运输'
    elsif n.include?('航空')
      industry = '航空'
      broad ||= '交通运输'
    elsif n.include?('钢铁') || n.end_with?('钢')
      industry = '钢铁'
      broad ||= '原材料'
    elsif n.include?('煤') || n.include?('能源')
      industry = '煤炭'
      broad ||= '能源'
    elsif n.include?('铜') || n.include?('锌') || n.include?('钼') || n.include?('金') || n.include?('铝')
      industry = '有色金属'
      broad ||= '原材料'
    elsif n.include?('电力') || n.include?('燃气') || n.include?('环保')
      industry = '电力'
      broad ||= '公用事业'
    elsif n.include?('药') || n.include?('医') || n.include?('医疗')
      industry = industry_guess_for_medical(n)
      broad ||= '医药卫生'
    elsif n.include?('传媒')
      industry = '传媒'
      broad ||= '传媒'
    elsif n.include?('电气') || n.include?('电器') || n.include?('机械') || n.include?('航空') || n.include?('航') || n.include?('电子')
      broad ||= '工业'
    end

    if industry && broad.nil?
      broad = industry_to_broad[industry] || broad_guess(industry)
    end

    categories = []
    categories << industry if industry
    categories << broad if broad
    categories.uniq
  end

  def industry_guess_for_medical(name)
    return '中药' if name.include?('中药') || name.include?('天士力')
    return '医疗服务' if name.include?('医疗')
    '化学制药'
  end

  def infer_by_keyword(board)
    b = board.to_s
    return ['半导体', '信息技术'] if b.include?('半导体')
    return ['电池', '工业'] if b.include?('电池')
    return ['医疗器械', '医药卫生'] if b.include?('医疗器械')
    return ['创新药', '医药卫生'] if b.include?('创新药')
    return ['生物制品', '医药卫生'] if b.include?('生物') || b.include?('疫苗')
    return ['光伏设备', '工业'] if b.include?('光伏') || b.include?('储能')
    return ['航空装备', '工业'] if b.include?('军工') || b.include?('航天') || b.include?('无人机')
    return ['电力', '公用事业'] if b.include?('电力')
    return ['煤炭', '能源'] if b.include?('煤炭')
    return ['有色金属', '原材料'] if b.include?('有色') || b.include?('稀土') || b.include?('黄金')
    return ['证券', '金融'] if b.include?('证券')
    return ['银行', '金融'] if b.include?('银行')
    return ['白酒', '消费'] if b.include?('白酒')
    return ['乳制品', '消费'] if b.include?('乳业')
    return ['家电', '可选消费'] if b.include?('家电')
    nil
  end

  def broad_guess(industry)
    return '交通运输' if industry.include?('港') || industry.include?('航空') || industry.include?('铁路') || industry.include?('航运') || industry.include?('高速公路')
    return '金融' if industry.include?('证券') || industry.include?('保险') || industry.include?('银行')
    return '消费' if industry.include?('食品') || industry.include?('饮料') || industry.include?('白酒') || industry.include?('乳') || industry.include?('家电')
    return '医药卫生' if industry.include?('医') || industry.include?('药') || industry.include?('医疗')
    nil
  end
end
