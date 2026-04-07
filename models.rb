require 'active_record'
require 'dotenv/load'
require 'httplog'

# HttpLog 配置
HttpLog.configure do |config|
  config.enabled = true
  config.log_headers = false
  config.log_data = false # 不打印请求 body
  config.log_response = false # 不打印响应 body
  config.compact_log = true # 使用单行日志
  config.color = :blue
end

# 数据库配置
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

# 股票信息模型
# 字段:
# - name: 股票名称
# - secid: 东方财富 ID (市场.代码)
# - code: 股票代码
# - market_id: 市场 ID (0:深证, 1:上证)
# - dividend_yield: 历史股息率 (根据最后一次完整年度分红计算)
# - expected_dividend_yield: 预期股息率 (基于最近 12 个月分红和最新股价)
# - current_price: 最新收盘价
# - high_30d, low_30d, pos_30d: 30天滚动最高、最低及位置
# - high_1y, low_1y, pos_1y: 1年滚动最高、最低及位置
# - high_3y, low_3y, pos_3y: 3年滚动最高、最低及位置
# - high_5y, low_5y, pos_5y: 5年滚动最高、最低及位置
# - price_position: 全量价格百分位 (0-1)
# - valuation_label: 估值标签
class Stock < ActiveRecord::Base
  has_many :price_histories, dependent: :destroy
  has_many :dividends, dependent: :destroy
  has_many :categorizations, dependent: :destroy
  has_many :categories, through: :categorizations
end

# 分类模型
class Category < ActiveRecord::Base
  has_many :categorizations, dependent: :destroy
  has_many :stocks, through: :categorizations
end

# 股票与分类的关联模型
class Categorization < ActiveRecord::Base
  belongs_to :stock
  belongs_to :category
end

# 价格历史行情模型
# 字段:
# - pe: 历史市盈率
# - pb: 历史市净率
class PriceHistory < ActiveRecord::Base
  belongs_to :stock
end

# 分红历史模型
# 字段:
# - stock_id: 关联股票 ID
# - report_date: 报告期
# - notice_date: 公告日期
# - plan_description: 分红方案描述
# - cash_dividend: 每股派现
# - bonus_issue: 每股送股
# - rights_issue: 每股转增
# - dividend_yield: 股息率
class Dividend < ActiveRecord::Base
  belongs_to :stock
end
