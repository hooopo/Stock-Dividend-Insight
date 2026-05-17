# 数据表与字段说明（数据字典）

本文档用于解释本项目数据库中的主要数据表、字段含义、单位与来源，以及它们在同步/计算链路中的位置。

## 总览

主要表：

- `stocks`：股票主表（看板展示与筛选/排序主要基于此表字段）
- `price_histories`：日频 K 线与历史估值（PE/PB）
- `dividends`：分红明细
- `roe_histories`：ROE 历史
- `categories` / `categorizations`：行业/主题分类与关联
- `treasury_yields`：国债收益率序列（宏观页）

## stocks（股票主表）

用途：承载“当前最新状态 + 派生指标”。列表页的绝大多数列都来自这里。

### 基础身份字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | string | 股票名称 |
| `code` | string | 6 位证券代码（如 `000651`） |
| `market_id` | integer | 市场：`0=深市`，`1=沪市` |
| `secid` | string | 统一标识：`market_id.code`（如 `0.000651`） |

### 行情快照字段（实时/准实时）

来源：`QuoteSnapshotSyncer`（腾讯行情接口）

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `current_price` | decimal | 最新价（元） |
| `turnover_rate` | decimal | 换手率（%） |
| `market_cap` | decimal | 总市值（元） |
| `volume` | bigint | 成交量（手） |
| `avg_price` | decimal | 成交均价（元） |
| `pe_ttm` | decimal | PE(TTM) |
| `pb` | decimal | PB |
| `total_shares` | bigint | 总股本（股） |

### 财务快照字段（财报口径）

来源：`FinanceSnapshotSyncer`（东方财富数据中心）

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `finance_report_date` | date | 财报期 |
| `revenue_yoy` | decimal | 营收同比（%） |
| `net_profit_yoy` | decimal | 净利同比（%） |
| `net_profit_yoy_deducted` | decimal | 扣非净利同比（%） |
| `total_assets` | bigint | 总资产（元） |
| `total_liabilities` | bigint | 总负债（元） |
| `asset_liability_ratio` | decimal | 资产负债率（%）≈ `total_liabilities / total_assets` |
| `interest_debt_ratio` | decimal | 有息负债率（%） |
| `peg` | decimal | PEG ≈ `PE(TTM) / 净利同比`（仅在二者为正时计算） |
| `peg_level` | integer | PEG 分级（用于筛选与提示） |

### ROE 相关字段

来源：`RoeHistorySyncer`（东方财富数据中心）+ 计算规则

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `roe_jq` | decimal | ROE（加权，%） |
| `roe_kc_jq` | decimal | 扣非 ROE（加权，%） |
| `roe_report_date` | date | ROE 对应财报期 |
| `roe_report_type` | string | 报表类型（年报/季报等） |
| `roe_level` | integer | ROE 分级（依据阈值划分） |
| `roe_5y_avg_ge_12` | boolean | 近 5 年 ROE 均值 ≥ 12% |
| `roe_5y_min_ge_8` | boolean | 近 5 年 ROE 最低值 ≥ 8% |

### 分红与股息率字段

来源：`DividendSyncer`（东方财富分红） + `ValuationCalculator` 计算

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `dividend_yield` | decimal | 历史股息率（%）：最近一个年度累计派现 / 最新价 |
| `expected_dividend_yield` | decimal | 预期股息率（%）：近 12 个月派现累计 / 最新价（若 12 个月为 0，会退化到最近一年报年度累计派现） |
| `has_dividend_5y` | boolean | 连续 5 年有分红（按年度是否存在 `cash_dividend > 0` 判断） |

### 估值分位与等级字段

来源：`ValuationHistorySyncer` 写入 `price_histories.pe_ttm/pb` + `ValuationCalculator` 计算

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `pb_level` | integer | PB 分级（用于筛选/提示） |
| `pb_percentile` | decimal | PB 历史分位（0-1） |
| `pb_percentile_level` | integer | PB 分位等级（离散化） |
| `pe_level` | integer | PE 分级（用于筛选/提示） |
| `pe_percentile` | decimal | PE(TTM) 历史分位（0-1） |
| `pe_percentile_level` | integer | PE 分位等级（离散化） |

### 价格分位与位置字段

来源：`PriceHistorySyncer` 写入 `price_histories` + `PriceMetricsCalculator`/`ValuationCalculator` 计算

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `high_30d` / `low_30d` | decimal | 近 30 天最高/最低 |
| `high_90d` / `low_90d` | decimal | 近 90 天最高/最低 |
| `pos_30d` | decimal | 近 30 天价格分位（0-1） |
| `pos_90d` | decimal | 近 90 天价格分位（0-1） |
| `high_1y` / `low_1y` | decimal | 近 1 年最高/最低 |
| `pos_1y` | decimal | 近 1 年价格分位（0-1） |
| `high_3y` / `low_3y` | decimal | 近 3 年最高/最低 |
| `pos_3y` | decimal | 近 3 年价格分位（0-1） |
| `high_5y` / `low_5y` | decimal | 近 5 年最高/最低 |
| `pos_5y` | decimal | 近 5 年价格分位（0-1） |
| `high_all` / `low_all` | decimal | 全量（通常指10年内）最高/最低 |
| `price_position` | decimal | 全量（10年内）价格分位（0-1） |
| `drop_30d` | decimal | 30 日跌幅（%）：`(30 天窗口起点收盘 - 当前价) / 起点收盘 * 100`；下跌为正、上涨为负 |

### FCF（自由现金流）相关字段

来源：`FinanceSnapshotSyncer`（东方财富）+ 计算

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `fcff_back` | decimal | 自由现金流（数据源口径，回溯用） |
| `fcf_yield` | decimal | FCF Yield（%）：`fcff_back / market_cap * 100` |
| `fcf_ev` | decimal | FCF/EV（%）：`fcff_back / (market_cap + 有息负债估算) * 100`，其中有息负债估算 ≈ `interest_debt_ratio% * total_liabilities` |

### 同步状态字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `last_synced_at` | datetime | K 线同步成功标记（当天已同步则可跳过） |

## price_histories（日频行情与历史估值）

用途：承载 K 线（日线）与历史估值（用于 PE/PB 分位计算、个股图表等）。

### 行情字段

来源：`PriceHistorySyncer`（新浪财经）

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `stock_id` | references | 关联股票 |
| `date` | date | 交易日 |
| `open` / `high` / `low` / `close` | decimal | OHLC（元） |
| `volume` | bigint | 成交量（手） |
| `amount` | decimal | 成交额（部分数据源可能为空） |
| `amplitude` | decimal | 振幅（部分数据源可能为空） |

### 历史估值字段

来源：`ValuationHistorySyncer`（东方财富数据中心）

| 字段 | 类型 | 说明 |
|---|---|---|
| `pe_ttm` | decimal | 当日 PE(TTM) |
| `pb` | decimal | 当日 PB |

## dividends（分红明细）

用途：承载每个报告期的派现/送转信息，用于计算股息率与“连续分红”等。

来源：`DividendSyncer`（东方财富）

| 字段 | 类型 | 说明/单位 |
|---|---|---|
| `stock_id` | references | 关联股票 |
| `report_date` | date | 报告期（用于按年汇总） |
| `notice_date` | date | 公告日 |
| `plan_description` | string | 原始方案描述（如 “10 派 1.6”） |
| `cash_dividend` | decimal | 每股派现（元/股） |
| `bonus_issue` | decimal | 每股送股（股/股） |
| `rights_issue` | decimal | 每股转增（股/股） |
| `dividend_yield` | decimal | 数据源返回的参考股息率（%）（可能为空） |

## roe_histories（ROE 历史）

用途：承载 ROE 多期记录，用于计算“近 5 年 ROE 均值/最低”等稳定性指标。

来源：`RoeHistorySyncer`（东方财富）

| 字段 | 类型 | 说明 |
|---|---|---|
| `stock_id` | references | 关联股票 |
| `report_date` | date | 财报期 |
| `report_type` | string | 报表类型 |
| `report_year` | string | 报告年度（字符串口径） |
| `roe_jq` | decimal | ROE（加权，%） |
| `roe_kc_jq` | decimal | 扣非 ROE（加权，%） |
| `notice_date` | date | 公告日 |
| `update_date` | date | 更新日 |

## categories / categorizations（分类）

用途：列表页的“分类选择/排除”筛选，以及个股 tooltip 展示等。

| 表 | 字段 | 类型 | 说明 |
|---|---|---|---|
| `categories` | `name` | string | 分类名称（唯一） |
| `categorizations` | `stock_id` | references | 股票 |
| `categorizations` | `category_id` | references | 分类 |

## treasury_yields（国债收益率）

用途：宏观页面展示与估值参考（如 CN 10Y）。

来源：`TreasuryYieldSyncer`（中债/Chinabond）

| 字段 | 类型 | 说明 |
|---|---|---|
| `date` | date | 日期 |
| `country` | string | 国家（如 `CN`） |
| `tenor` | string | 期限（如 `10Y`） |
| `series_id` | string | 序列 ID |
| `yield_pct` | decimal | 收益率（%） |
| `source` | string | 数据来源 |

## 同步与计算链路（字段从哪里来）

为了快速定位“哪个字段应该由哪个任务填充”，可以按下列映射理解：

- `QuoteSnapshotSyncer` → `stocks.current_price/market_cap/turnover_rate/volume/avg_price/pe_ttm/pb/total_shares`
- `PriceHistorySyncer` → `price_histories`（OHLCV）
- `DividendSyncer` → `dividends`（派现/送转）
- `ValuationHistorySyncer` → `price_histories.pe_ttm/pb`（用于分位）
- `FinanceSnapshotSyncer` → `stocks.finance_*`、`asset_liability_ratio`、`interest_debt_ratio`、`peg`、`fcff_back`、`fcf_yield`、`fcf_ev`
- `RoeHistorySyncer` → `roe_histories` + `stocks.roe_*`
- `PriceMetricsCalculator` → `stocks.pos_30d/pos_1y/pos_3y/pos_5y`、`high_*/low_*`、`drop_30d`
- `ValuationCalculator` → `stocks.dividend_yield/expected_dividend_yield/has_dividend_5y`、`price_position`、`pb/pe` 分位与等级、`valuation_label`

