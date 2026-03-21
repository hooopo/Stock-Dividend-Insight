require 'active_record'
require 'dotenv/load'

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
# - pe: 当前市盈率 (PE TTM)
# - pb: 当前市净率 (PB)
# - price_position: 当前价格在历史价格区间的百分位 (0-1)
# - dividend_yield_position: 当前股息率在历史股息率区间的百分位 (0-1)
# - pe_position: PE 历史百分位 (0-1)
# - pb_position: PB 历史百分位 (0-1)
# - comprehensive_position: 综合位置 (0.4*Price + 0.3*PE + 0.3*PB)
# - valuation_label: 估值标签
class Stock < ActiveRecord::Base
  has_many :price_histories, dependent: :destroy
  has_many :dividends, dependent: :destroy
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
