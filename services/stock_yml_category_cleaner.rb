class StockYmlCategoryCleaner
  def initialize(file_path: 'stocks-pro.yml', remove_categories: [])
    @file_path = file_path
    @remove_categories = Array(remove_categories).compact.map { |x| x.to_s.strip }.reject(&:empty?).uniq
  end

  def run
    return if @remove_categories.empty?
    lines = File.read(@file_path, encoding: 'UTF-8').lines
    removed = 0

    out =
      lines.reject do |line|
        next false unless line.match?(/^\s+-\s+/)
        name = line.sub(/^\s+-\s+/, '').strip
        if @remove_categories.include?(name)
          removed += 1
          true
        else
          false
        end
      end

    File.write(@file_path, out.join)
    removed
  end
end

