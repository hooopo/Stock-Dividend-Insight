require 'date'

module DividendMetrics
  module_function

  def cash_value(dividend)
    raw = field_value(dividend, :cash_dividend)
    raw ? raw.to_f : 0.0
  end

  def event_date(dividend)
    field_value(dividend, :ex_dividend_date) ||
      field_value(dividend, :notice_date) ||
      field_value(dividend, :report_date)
  end

  def fiscal_year(dividend)
    raw_year = field_value(dividend, :fiscal_year)
    year = raw_year.to_i
    return year if year > 0

    date = field_value(dividend, :ex_dividend_date) || field_value(dividend, :report_date)
    date&.year
  end

  def annual_cash(dividends)
    sums = Hash.new(0.0)
    Array(dividends).each do |dividend|
      year = fiscal_year(dividend)
      next unless year && year > 0
      sums[year] += cash_value(dividend)
    end
    sums
  end

  def normalized_rows(dividends, future_dividends: [], base_date: Date.today)
    rows = []

    Array(dividends).each do |dividend|
      rows << {
        report_date: field_value(dividend, :report_date),
        notice_date: field_value(dividend, :notice_date),
        ex_dividend_date: field_value(dividend, :ex_dividend_date),
        fiscal_year: fiscal_year(dividend),
        cash_dividend: cash_value(dividend),
        plan_description: field_value(dividend, :plan_description)
      }
    end

    Array(future_dividends).each do |dividend|
      ex_date = field_value(dividend, :ex_dividend_date)
      next unless ex_date && ex_date <= base_date

      rows << {
        report_date: nil,
        notice_date: field_value(dividend, :notice_date),
        ex_dividend_date: ex_date,
        fiscal_year: ex_date.year,
        cash_dividend: (field_value(dividend, :cash_dividend_per_share) || field_value(dividend, :cash_dividend)).to_f,
        plan_description: field_value(dividend, :plan_description)
      }
    end

    seen = {}
    rows.each_with_object([]) do |row, merged|
      key = [
        row[:ex_dividend_date]&.to_s,
        row[:fiscal_year].to_i,
        format('%.6f', row[:cash_dividend].to_f),
        row[:plan_description].to_s
      ].join('|')
      next if seen[key]
      seen[key] = true
      merged << row
    end
  end

  def ttm_cash(dividends, base_date: Date.today)
    cutoff = base_date - 365
    Array(dividends).sum do |dividend|
      date = event_date(dividend)
      next 0.0 unless date && date > cutoff && date <= base_date
      cash_value(dividend)
    end
  end

  def latest_cash_year(dividends)
    annual_cash(dividends).keys.max
  end

  def latest_cash_for_year(dividends)
    sums = annual_cash(dividends)
    year = sums.keys.max
    [year, year ? sums[year].to_f : nil]
  end

  def trailing_years(dividends, count: 3)
    max_year = latest_cash_year(dividends)
    return [] unless max_year
    ((max_year - count + 1)..max_year).to_a
  end

  def consecutive_years(dividends)
    sums = annual_cash(dividends)
    positive_years = sums.select { |_, v| v.to_f > 0.0 }.keys.map(&:to_i)
    return nil if positive_years.empty?

    y = positive_years.max
    n = 0
    while sums[y - n].to_f > 0.0
      n += 1
    end
    n > 0 ? n : nil
  end

  def field_value(record, field)
    if record.respond_to?(field)
      record.public_send(field)
    elsif record.is_a?(Hash)
      record[field] || record[field.to_s]
    end
  end
end
