# 数据分析项目集

两个端到端独立分析项目，分别对应数据分析岗的两类核心工作：**从已有数据里找问题**，和**设计实验验证假设**。

| 项目 | 类型 | 技术栈 | 一句话结论 |
|---|---|---|---|
| [Olist 电商业务指标分析](./01-olist-ecommerce/) | 已有数据 → 业务洞察 | MySQL · Excel · Power BI | 表面复购率 3.04%，剔除拆单后真实仅 1.49% |
| [Cookie Cats A/B 测试](./02-cookie-cats-abtest/) | 实验设计 → 统计验证 | Python · scipy · statsmodels | 7 日留存差异统计显著，但效应量极小 |

---

## 为什么是这两个项目

数据分析岗日常做的就这两类事，所以我刻意各做了一个：

**项目一考的是业务理解与口径设计。** 数据摆在那里，难的不是算出来，是问对问题、定对口径。这个项目里最有价值的发现不是"复购率是多少"，而是"原来那个 3.04% 是假的"。

**项目二考的是统计严谨与风险控制。** 结论显著不等于值得上线。这个项目里最有价值的判断不是"p < 0.05"，而是"p = 0.0016 但效应量只有 0.021，要不要因此改产品"。

---

## 项目一：Olist 巴西电商业务指标分析

**数据规模**：98,208 笔订单，2016-09 至 2018-08，9 张业务表

**做了什么**：
- 用 MySQL 建 9 张表与视图，把原始业务表整理成统一的订单级明细表 `v_orders_base`
- 统一口径后计算 7 个核心指标：GMV、订单数、客单价、复购率、次月留存、签收率、差评率
- 产出 Excel 与 Power BI 两套看板

**三个核心发现**：

1. **增长靠拉单量，不靠提客单价** —— GMV 涨 7.1 倍，订单量涨 8.2 倍，客单价反而跌了 13.4%（152.6 → 132.2）
2. **复购率被高估一倍** —— 表面 3.04%，但 51% 的复购买家 30 天内就回购，平均间隔仅 5.2 天，其中 897 个是同日拆单。剔除后真实回访型复购只有 1.49%
3. **履约是差评的最大杠杆** —— 准时送达差评率 9.28%，延迟 1–7 天跳到 49.42%。延迟订单只占 6.65%，却贡献了 32.4% 的差评

→ [完整报告](./01-olist-ecommerce/report.md) · [SQL 脚本](./01-olist-ecommerce/sql/)

---

## 项目二：Cookie Cats 手游 A/B 测试

**数据规模**：90,189 名玩家，随机对照实验

**实验背景**：Cookie Cats 是一款关卡制消除手游，原设计在玩家通过第 30 关时弹出强制门槛。实验把门槛后移到第 40 关，检验"减少早期打断能否提升留存"。

**做了什么**：
- 数据质量检查：重复用户、缺失值、样本比例（SRM 检验）
- 主指标：次日留存与 7 日留存，卡方检验 + 两比例 z 检验 + 置信区间 + 效应量
- 次指标：14 天游戏局数，因严重右偏（偏度 163.71）改用 Mann-Whitney U 检验
- 事后分析：样本量回溯、MDE 计算、Bonferroni 多重比较校正

**核心结论**：

| 指标 | gate_30 | gate_40 | 差异 | p 值 | 判断 |
|---|---|---|---|---|---|
| 次日留存 | 44.82% | 44.23% | +0.59pp | 0.0755 | 不显著 |
| 7 日留存 | 19.02% | 18.20% | +0.82pp | 0.0016 | **显著**（h = 0.021，小效应） |

**业务建议**：维持 gate 在第 30 关。早期门槛不只是阻碍，也起到了筛选高意愿用户、建立游戏节奏的作用。

**主动披露的局限**：SRM 检验未通过（p = 0.0086，偏差 0.88pp），随机分组存在瑕疵，结论需降级使用。

→ [完整报告](./02-cookie-cats-abtest/report.md) · [分析脚本](./02-cookie-cats-abtest/ab_test.py)

---

## 技术栈

| 类别 | 具体能力 |
|---|---|
| **SQL** | MySQL 8.0；CTE、窗口函数（RANK / LAG / ROW_NUMBER / SUM OVER）、多表关联、执行计划基础 |
| **Python** | pandas 数据清洗与聚合；scipy 统计检验；statsmodels 功效分析 |
| **BI 工具** | Power BI（DAX 度量值、时间智能、多页看板）；Excel（透视表、条件格式、数据验证） |
| **统计方法** | 假设检验、置信区间、效应量（Cohen's h）、功效分析与样本量规划、SRM 检验、多重比较校正 |

---

## 目录结构

```
data-analysis-portfolio/
├── 01-olist-ecommerce/
│   ├── README.md
│   ├── report.md                     # 完整分析报告
│   └── sql/
│       ├── 01_schema_mysql.sql       # 建表与索引
│       ├── 02_metric_views_mysql.sql # 7 个核心指标视图
│       ├── 03_metric_views_postgres.sql # PostgreSQL 方言版本
│       └── 04_reimport_mysql80.sql   # MySQL 8.0 重导入脚本
└── 02-cookie-cats-abtest/
    ├── README.md
    ├── report.md                     # 完整分析报告
    ├── ab_test.py                    # 分析脚本（7 个模块）
    └── requirements.txt
```

---

## 关于数据

两个项目均使用公开数据集，**不含任何真实用户隐私信息**：

- Olist：[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)（Kaggle）
- Cookie Cats：[Cookie Cats A/B Test](https://www.kaggle.com/datasets/yufengsui/mobile-games-ab-testing)（Kaggle）

数据文件体积较大，未纳入仓库。复现步骤见各项目 README。

---

## 复现方式

**项目一**需要本地 MySQL 8.0+，按 `sql/` 目录下 01 → 02 顺序执行，再导入 Kaggle 原始 CSV。

**项目二**只需 Python 环境：

```bash
cd 02-cookie-cats-abtest
pip install -r requirements.txt
python ab_test.py
```

脚本会自动输出 7 个模块的分析结果，约 10 秒完成。
