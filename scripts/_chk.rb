raw = File.readlines('scripts/gt3_pages.rb')[79..151].join
m = raw.match(/WHITELIST_RAW\s*=\s*<<~EOF(.*?)EOF/m)
lines = m[1].split(/\n/).map(&:strip).reject(&:empty?)
map = {}
lines.each do |l|
  parts = l.split('|').map(&:strip)
  next unless parts.size >= 7
  code = parts[3].rjust(6, '0')
  next unless code.match?(/^\d{6}$/)
  map[code] = parts
end
puts "WHITELIST_RAW 中 601088: " + (map['601088'] ? map['601088'].inspect : 'NOT FOUND')
puts "WHITELIST_RAW 总行数 (只看7字段合法): #{map.size}"
