# A股捡垃圾

这是一个基于 Ruby 的 A 股股票分红数据同步与分析工具。它可以自动从新浪财经和东方财富抓取历史行情及分红数据，并计算股票的**历史股息率**与**预期股息率**。

## 功能特点

- **多数据源同步**: 
  - 使用新浪财经 API 同步历史 K 线数据（日线级）。
  - 使用东方财富 API 同步详细的历史分红方案。
- **智能股息率计算**:
  - **历史股息率**: 取股票最后一次完整年度分红累计额 / 最新股价。
  - **预期股息率**: 取最近 12 个月内的分红累计额 / 最新股价。
- **分红方案解析**: 自动将“10派X元”等文字描述转换为数值。
- **数据库驱动**: 使用 PostgreSQL 存储数据，支持增量更新。
- **现代化架构**: 采用 `ActiveRecord` ORM，支持 `rake migrate` 和 `dotenv` 配置。

## 快速开始

### 1. 安装依赖

确保你已经安装了 Ruby 和 PostgreSQL。

```bash
bundle install
```

### 2. 配置环境

复制并编辑 `.env` 文件：

```bash
cp .env.example .env # 如果没有 example，直接创建 .env
```

在 `.env` 中设置你的数据库连接：
```text
# 支持本地数据库格式：
DATABASE_URL=postgres://localhost/stock_dividend_insight

# 也支持远程数据库（如 Neon），支持 postgresql:// 协议及 SSL 参数：
DATABASE_URL=postgresql://user:pass@host/dbname?sslmode=require
```

### 3. 初始化数据库

```bash
rake setup
```

### 4. 同步数据

首次运行建议全量同步，之后可使用增量同步：

```bash
# 全量同步（抓取 1000 条历史 K 线）
ruby sync_stocks.rb

# 增量同步（仅抓取最近 20 条 K 线，适合每日运行）
ruby sync_stocks.rb --incremental

# 启动 Web 服务器
ruby app.rb
```

## Web 界面说明

系统提供了一个基于 Sinatra 的轻量级 Web 界面，你可以访问 `http://localhost:4567` 查看：

- **股票列表**: 展示所有 102 只股票的详细信息。
- **多维排序**: 点击表头可按股息率、价格位置（30d/1y/3y/5y）等进行升序或降序排列。
- **可视化标注**: 自动高亮处于“底部区域”的低位机会。

## 核心模型说明

### 1. Stock (股票信息表)
存储股票的基本信息以及计算出的股息率指标。

| 字段名 | 类型 | 描述 | 备注 |
| :--- | :--- | :--- | :--- |
| `name` | String | 股票名称 | e.g., 平安银行 |
| `secid` | String | 东方财富格式 ID | e.g., 0.000001 |
| `code` | String | 股票代码 | e.g., 000001 |
| `market_id` | Integer | 市场 ID | 0: 深证, 1: 上证 |
| `dividend_yield` | Decimal | 历史股息率 (%) | 最后一次完整年度分红累计额 / 最新股价 |
| `expected_dividend_yield` | Decimal | 预期股息率 (%) | 最近 12 个月内的分红累计额 / 最新股价 |
| `current_price` | Decimal | 最新收盘价 | 数据库中最近一个交易日的收盘价 |
| `high_30d` | Decimal | 30天最高价 | |
| `low_30d` | Decimal | 30天最低价 | |
| `pos_30d` | Decimal | 30天价格位置 | (当前价-最低)/(最高-最低) |
| `high_1y` | Decimal | 1年最高价 | |
| `low_1y` | Decimal | 1年最低价 | |
| `pos_1y` | Decimal | 1年价格位置 | |
| `high_3y` | Decimal | 3年最高价 | |
| `low_3y` | Decimal | 3年最低价 | |
| `pos_3y` | Decimal | 3年价格位置 | |
| `high_5y` | Decimal | 5年最高价 | |
| `low_5y` | Decimal | 5年最低价 | |
| `pos_5y` | Decimal | 5年价格位置 | |
| `price_position` | Decimal | 历史全量价格位置 (0-1) | (当前价 - 历史最低) / (历史最高 - 历史最低) |

### 2. PriceHistory (价格历史行情表)
存储每日的交易行情数据。

| 字段名 | 类型 | 描述 | 备注 |
| :--- | :--- | :--- | :--- |
| `stock_id` | References | 关联股票 ID | 外键关联 `stocks` 表 |
| `date` | Date | 交易日期 | |
| `open` | Decimal | 开盘价 | |
| `close` | Decimal | 收盘价 | |
| `high` | Decimal | 最高价 | |
| `low` | Decimal | 最低价 | |
| `volume` | BigInt | 成交量 | 单位：手 |

### 3. Dividend (分红历史表)
存储详细的分红方案及其实施日期。

| 字段名 | 类型 | 描述 | 备注 |
| :--- | :--- | :--- | :--- |
| `stock_id` | References | 关联股票 ID | 外键关联 `stocks` 表 |
| `report_date` | Date | 报告期 | e.g., 2023-12-31 |
| `notice_date` | Date | 公告日期 | |
| `plan_description` | String | 分红方案描述 | e.g., 10派1.60元 |
| `cash_dividend` | Decimal | 每股派现 | 单位：元 |
| `bonus_issue` | Decimal | 每股送股 | 单位：股 |
| `rights_issue` | Decimal | 每股转增 | 单位：股 |
| `dividend_yield` | Decimal | 当时股息率 (%) | 抓取自 API 的实时参考值 |

## 常用命令

- **查看高股息率股票排名**:
  ```bash
  psql -d stock_dividend_insight -c "SELECT name, dividend_yield, expected_dividend_yield FROM stocks WHERE expected_dividend_yield IS NOT NULL ORDER BY expected_dividend_yield DESC LIMIT 20;"
  ```
- **数据库迁移**:
  - `rake migrate`: 执行迁移。
  - `rake rollback`: 回退迁移。

## 数据来源

- 历史行情: [新浪财经](https://finance.sina.com.cn/)
- 分红数据: [东方财富网](https://www.eastmoney.com/)
