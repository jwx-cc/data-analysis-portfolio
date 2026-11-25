-- =====================================================================
-- 项目一 · 业务指标 SQL（MySQL 8.0+）
-- 对应 D1 数据质量初检 + D2 七个核心指标
-- 每个指标上方都有「口径」注释，这段注释直接抄进你的项目文档
-- =====================================================================

USE olist;

-- #####################################################################
-- 第 0 部分：数据质量初检（D1 用，每条都要跑，结果写进数据字典）
-- #####################################################################

-- 0.1 时间范围：确认数据边界
SELECT MIN(order_purchase_timestamp) AS first_order_ts,
       MAX(order_purchase_timestamp) AS last_order_ts,
       COUNT(*) AS total_orders
FROM orders;
-- 你会看到 2016-09-04 到 2018-10-17，但 2016-09~12 只有几百单，
-- 2018-09 之后只有零星几单 → 做趋势必须剔除首尾，否则图表两头是断崖

-- 0.2 缺失率：哪些字段能用，哪些不能用
SELECT
  ROUND(SUM(order_approved_at IS NULL)             / COUNT(*) * 100, 2) AS approved_null_pct,
  ROUND(SUM(order_delivered_carrier_date IS NULL)  / COUNT(*) * 100, 2) AS carrier_null_pct,
  ROUND(SUM(order_delivered_customer_date IS NULL) / COUNT(*) * 100, 2) AS delivered_null_pct,
  ROUND(SUM(order_estimated_delivery_date IS NULL) / COUNT(*) * 100, 2) AS estimated_null_pct
FROM orders;

-- 0.3 孤儿订单：有订单主表但没有任何商品明细
-- Olist 里存在 775 单左右，这类订单不能计入 GMV，否则分母虚高
SELECT COUNT(*) AS orders_without_items
FROM orders o
LEFT JOIN order_items i ON i.order_id = o.order_id
WHERE i.order_id IS NULL;

-- 0.4 主键唯一性验证（面试常问：你怎么保证没重复计数）
SELECT COUNT(*) AS rows_cnt, COUNT(DISTINCT order_id) AS distinct_orders
FROM orders;

-- 0.5 订单状态分布：先看清哪些状态该排除
SELECT order_status, COUNT(*) AS cnt,
       ROUND(COUNT(*) / (SELECT COUNT(*) FROM orders) * 100, 2) AS pct
FROM orders
GROUP BY order_status
ORDER BY cnt DESC;

-- 0.6 支付金额与商品金额是否对得上（运费差异）
SELECT ROUND(SUM(p.payment_value), 2) AS total_paid,
       ROUND(SUM(i.price + i.freight_value), 2) AS total_price_freight,
       ROUND(SUM(p.payment_value) - SUM(i.price + i.freight_value), 2) AS diff
FROM (SELECT order_id, SUM(payment_value) AS payment_value FROM order_payments GROUP BY order_id) p
JOIN (SELECT order_id, SUM(price) AS price, SUM(freight_value) AS freight_value FROM order_items GROUP BY order_id) i
  ON i.order_id = p.order_id;


-- #####################################################################
-- 第 1 部分：统一明细视图（所有指标都基于它，口径才不会打架）
-- #####################################################################
DROP VIEW IF EXISTS v_orders_base;
CREATE VIEW v_orders_base AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_unique_id,
  c.customer_state,
  o.order_status,
  o.order_purchase_timestamp                          AS purchase_ts,
  DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')    AS ym,
  o.order_delivered_customer_date                     AS delivered_ts,
  o.order_estimated_delivery_date                     AS estimated_ts,
  pay.pay_value,
  it.gmv,
  it.item_cnt
FROM orders o
JOIN customers c
  ON c.customer_id = o.customer_id
LEFT JOIN (
  SELECT order_id, SUM(payment_value) AS pay_value
  FROM order_payments GROUP BY order_id
) pay ON pay.order_id = o.order_id
LEFT JOIN (
  SELECT order_id, SUM(price) AS gmv, COUNT(*) AS item_cnt
  FROM order_items GROUP BY order_id
) it ON it.order_id = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable');
-- 说明：剔除取消单和无效单，保留其余状态。
--       gmv 为 NULL 表示该订单无商品明细，后续所有指标都要过滤 gmv IS NOT NULL。


-- #####################################################################
-- 指标 1：月度 GMV / 订单量 / AOV / GMV 环比
-- 口径：GMV = SUM(商品金额 price)，不含运费；剔除取消/无效单；
--       时间窗 2017-01 ~ 2018-08（剔除首尾不完整月份）
-- 业务含义：看盘子有多大、增长靠单量还是靠客单价
-- #####################################################################
WITH m AS (
  SELECT ym,
         SUM(gmv)                          AS gmv,
         COUNT(DISTINCT order_id)          AS order_cnt,
         COUNT(DISTINCT customer_unique_id) AS buyer_cnt
  FROM v_orders_base
  WHERE gmv IS NOT NULL
    AND ym BETWEEN '2017-01' AND '2018-08'
  GROUP BY ym
)
SELECT ym,
       ROUND(gmv, 2)                      AS gmv,
       order_cnt,
       buyer_cnt,
       ROUND(gmv / NULLIF(order_cnt, 0), 2)  AS aov,
       ROUND((gmv - LAG(gmv) OVER (ORDER BY ym))
             / NULLIF(LAG(gmv) OVER (ORDER BY ym), 0) * 100, 2) AS gmv_mom_pct
FROM m
ORDER BY ym;
-- 关键写法：
-- 1) 先聚合到月，再用 LAG 取上月值算环比。不能在明细行上直接 LAG，否则算的是「上一行」不是「上一月」。
-- 2) NULLIF(x,0) 防除零。MySQL 里除零默认返回 NULL 而不是报错，但写 NULLIF 更稳、别人读代码也更清楚。


-- #####################################################################
-- 指标 2：复购率（整体）
-- 口径：分子 = 下单次数 >= 2 的客户数；分母 = 有有效订单的客户数
--       客户身份用 customer_unique_id，不能用 customer_id
-- 业务含义：复购率低 = 拉新驱动，运营重点在首单转化；高 = 该做会员和召回
-- #####################################################################
WITH oc AS (
  SELECT customer_unique_id,
         COUNT(DISTINCT order_id) AS order_cnt,
         SUM(gmv)                 AS gmv
  FROM v_orders_base
  WHERE gmv IS NOT NULL
  GROUP BY customer_unique_id
)
SELECT COUNT(*)                                                        AS buyer_cnt,
       SUM(order_cnt >= 2)                                             AS repeat_buyer_cnt,
       ROUND(SUM(order_cnt >= 2) / COUNT(*) * 100, 2)                  AS repeat_rate_pct,
       ROUND(AVG(order_cnt), 2)                                        AS avg_orders_per_buyer,
       ROUND(SUM(CASE WHEN order_cnt >= 2 THEN gmv ELSE 0 END)
             / NULLIF(SUM(gmv), 0) * 100, 2)                           AS repeat_gmv_share_pct
FROM oc;
-- 预期结果：复购率约 3%（Olist 是典型的一单客户为主的数据集）。
-- 这个结果不是 bug，是业务事实，必须写进文档——面试官最烦「数据不对就改口径」。


-- #####################################################################
-- 指标 3：次月留存率（按首购月分群 / cohort）
-- 口径：cohort = 客户首次下单所在月；M1 留存 = 该群在第 2 个自然月再次下单的人数 / 群规模
-- 业务含义：衡量「买完还回来」的能力，比整体复购率更能看出运营改善效果
-- #####################################################################
WITH first_buy AS (
  SELECT customer_unique_id,
         DATE_FORMAT(MIN(purchase_ts), '%Y-%m') AS cohort_ym
  FROM v_orders_base
  WHERE gmv IS NOT NULL
  GROUP BY customer_unique_id
),
act AS (
  SELECT DISTINCT customer_unique_id, ym
  FROM v_orders_base
  WHERE gmv IS NOT NULL
)
SELECT f.cohort_ym,
       COUNT(DISTINCT f.customer_unique_id) AS cohort_size,
       COUNT(DISTINCT CASE
         WHEN a.ym = DATE_FORMAT(
                DATE_ADD(STR_TO_DATE(CONCAT(f.cohort_ym, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH),
                '%Y-%m')
         THEN a.customer_unique_id END)     AS m1_retained,
       ROUND(COUNT(DISTINCT CASE
         WHEN a.ym = DATE_FORMAT(
                DATE_ADD(STR_TO_DATE(CONCAT(f.cohort_ym, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH),
                '%Y-%m')
         THEN a.customer_unique_id END)
         / NULLIF(COUNT(DISTINCT f.customer_unique_id), 0) * 100, 2) AS m1_retention_pct
FROM first_buy f
LEFT JOIN act a
  ON a.customer_unique_id = f.customer_unique_id
WHERE f.cohort_ym BETWEEN '2017-01' AND '2018-07'
GROUP BY f.cohort_ym
ORDER BY f.cohort_ym;
-- 关键写法：
-- 1) 两段 CTE：first_buy 算每人的首购月（分群依据），act 算每人有哪些活跃月（行为事实），
--    最后 LEFT JOIN 把「群」和「后续行为」对上。
-- 2) 月份 +1 的写法最坑。MySQL 里字符串没法直接加月，必须 STR_TO_DATE 转日期 → DATE_ADD 加月 → 再 DATE_FORMAT 转回字符串。
-- 3) 用 COUNT(DISTINCT CASE WHEN ... END)，CASE 不写 ELSE 默认 NULL，COUNT 会自动忽略 NULL，正好实现条件计数。


-- #####################################################################
-- 指标 4：订单状态转化率（下单 → 支付 → 履约）
-- 口径：数据集没有曝光/加购埋点，无法算真实转化漏斗。
--       这里用订单状态链路替代：支付率 = 有支付时间 / 全部下单；签收率 = 已签收 / 已支付
-- 业务含义：支付率低 = 支付环节有问题；签收率低 = 物流/履约有问题
-- #####################################################################
SELECT COUNT(*)                                                   AS placed_orders,
       SUM(order_approved_at IS NOT NULL)                          AS paid_orders,
       SUM(order_delivered_customer_date IS NOT NULL)              AS delivered_orders,
       ROUND(SUM(order_approved_at IS NOT NULL) / COUNT(*) * 100, 2) AS pay_rate_pct,
       ROUND(SUM(order_delivered_customer_date IS NOT NULL)
             / NULLIF(SUM(order_approved_at IS NOT NULL), 0) * 100, 2) AS deliver_rate_pct
FROM orders;
-- 重要：写文档时必须主动声明「该数据集无前端埋点，转化率用订单状态链路近似」。
-- 主动说清局限 = 加分；假装自己有漏斗数据 = 面试被问穿。


-- #####################################################################
-- 指标 5：品类 GMV 占比 + 累计占比（帕累托）
-- 口径：按英文品类汇总 GMV，降序排列，窗口函数算累计占比
-- 业务含义：找出贡献 80% GMV 的核心品类，资源和库存优先保它们
-- #####################################################################
WITH cat AS (
  SELECT COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
         SUM(oi.price)              AS gmv,
         COUNT(DISTINCT oi.order_id) AS order_cnt,
         ROUND(AVG(oi.price), 2)     AS avg_price
  FROM order_items oi
  JOIN orders o
    ON o.order_id = oi.order_id
   AND o.order_status NOT IN ('canceled', 'unavailable')
  JOIN products p
    ON p.product_id = oi.product_id
  LEFT JOIN product_category_name_translation t
    ON t.product_category_name = p.product_category_name
  GROUP BY COALESCE(t.product_category_name_english, p.product_category_name, 'unknown')
)
SELECT category,
       ROUND(gmv, 2)                                              AS gmv,
       order_cnt,
       avg_price,
       ROUND(gmv / SUM(gmv) OVER () * 100, 2)                      AS gmv_share_pct,
       ROUND(SUM(gmv) OVER (ORDER BY gmv DESC
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(gmv) OVER () * 100, 2)                          AS cum_share_pct
FROM cat
ORDER BY gmv DESC;
-- 关键写法：
-- 1) 两个窗口函数：SUM() OVER () 是全表合计（分母），
--    SUM() OVER (ORDER BY gmv DESC ROWS ...) 是累计（分子）。这是帕累托分析的标准写法。
-- 2) COALESCE 三级兜底：英文品类 → 葡语品类 → 'unknown'。products 表有 610 个商品品类为空，
--    不兜底会丢 GMV，导致占比加起来不到 100%。
-- 3) JOIN orders 时把状态过滤写在 ON 里而不是 WHERE 里，语义更清晰（这里两种写法结果相同）。


-- #####################################################################
-- 指标 6：RFM 分层（本项目用 R×M 二维，原因见下）
-- 口径：R = 距数据截止日的最近一次购买天数（越小越好）
--       F = 下单次数
--       M = 累计消费金额
--       用 NTILE(5) 分 5 档，R 按升序分（天数越小分越高），F/M 按升序分
-- 业务含义：识别高价值客户做维护、沉睡客户做召回
-- #####################################################################
WITH base AS (
  SELECT customer_unique_id,
         DATEDIFF((SELECT MAX(purchase_ts) FROM v_orders_base), MAX(purchase_ts)) AS recency_days,
         COUNT(DISTINCT order_id) AS frequency,
         SUM(gmv)                 AS monetary
  FROM v_orders_base
  WHERE gmv IS NOT NULL
  GROUP BY customer_unique_id
),
scored AS (
  SELECT *,
         NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
         NTILE(5) OVER (ORDER BY frequency ASC)    AS f_score,
         NTILE(5) OVER (ORDER BY monetary ASC)     AS m_score
  FROM base
)
SELECT r_score,
       m_score,
       COUNT(*)                    AS customer_cnt,
       ROUND(SUM(monetary), 2)     AS gmv,
       ROUND(AVG(monetary), 2)     AS avg_monetary,
       ROUND(AVG(frequency), 2)    AS avg_frequency,
       CASE
         WHEN r_score >= 4 AND m_score >= 4 THEN '重要价值'
         WHEN r_score >= 4 AND m_score <  4 THEN '新客/潜力'
         WHEN r_score <  4 AND m_score >= 4 THEN '重要挽留'
         ELSE '流失/低价值'
       END AS segment
FROM scored
GROUP BY r_score, m_score
ORDER BY gmv DESC;
-- 关键写法：
-- 1) NTILE(5) 把客户按排序切成 5 等份，返回 1-5 的桶号。R 必须按 recency_days 升序，
--    这样天数最小（最近买过）的人落在第 5 桶 = 最高分。方向搞反是最常见的错误。
-- 2) 子查询取全局最大购买时间作为「今天」，因为数据集是历史快照，没有真实今天。
-- 3) 为什么用 R×M 而不是完整 RFM：这个数据集 F 几乎全是 1（复购率约 3%），
--    F 维度切出来全是同分，没有区分度。诚实降维比硬凑三维更专业——这句话写进文档。


-- #####################################################################
-- 指标 7（加分项）：配送延迟 vs 差评率
-- 口径：延迟天数 = 实际签收 - 承诺送达（>0 为延迟）；差评 = review_score <= 2
-- 业务含义：把「物流体验」量化成钱，是项目一最有说服力的一条结论
-- #####################################################################
SELECT CASE
         WHEN delay_days <= 0  THEN '1_准时或提前'
         WHEN delay_days <= 7  THEN '2_延迟1-7天'
         WHEN delay_days <= 14 THEN '3_延迟8-14天'
         ELSE                       '4_延迟14天以上'
       END                                    AS delay_bucket,
       COUNT(*)                               AS order_cnt,
       ROUND(AVG(review_score), 2)            AS avg_score,
       ROUND(AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) * 100, 2) AS bad_review_pct
FROM (
  SELECT o.order_id,
         DATEDIFF(o.order_delivered_customer_date, o.order_estimated_delivery_date) AS delay_days,
         r.review_score
  FROM orders o
  JOIN order_reviews r ON r.order_id = o.order_id
  WHERE o.order_delivered_customer_date IS NOT NULL
    AND o.order_estimated_delivery_date IS NOT NULL
    AND r.review_score IS NOT NULL
) t
GROUP BY delay_bucket
ORDER BY delay_bucket;
-- 关键写法：
-- 1) 先把「延迟天数」算在子查询里，外层再分桶。不要在同一个 SELECT 里既算延迟又按延迟分组。
-- 2) 分桶用 CASE 而不是等宽分箱，因为业务上「1 周内/2 周内」比「0-3.5 天」更好解释。
-- 3) 桶名前缀 1_/2_/3_ 是为了 ORDER BY 时按业务顺序排，而不是按字符串字典序排错。


-- #####################################################################
-- 第 2 部分：MySQL → PostgreSQL 差异提示（换库时要改的地方）
-- #####################################################################
-- 1) 类型：DATETIME → TIMESTAMP；VARCHAR 可保留；TINYINT → SMALLINT；AUTO_INCREMENT → GENERATED BY DEFAULT AS IDENTITY
-- 2) 建表尾部的 ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 全部删掉
-- 3) 导入：LOAD DATA LOCAL INFILE → COPY customers FROM '/path/x.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8');
-- 4) 日期格式化：DATE_FORMAT(ts,'%Y-%m') → to_char(ts,'YYYY-MM')
-- 5) 月份加减：STR_TO_DATE + DATE_ADD + DATE_FORMAT → date_trunc('month', ts) + interval '1 month'
-- 6) 日期差：DATEDIFF(a,b) → (a::date - b::date)
-- 7) 布尔求和：SUM(order_cnt >= 2) → SUM((order_cnt >= 2)::int)
-- 8) 整数除法（最容易错）：PG 里 COUNT()/COUNT() 会截断成 0，
--    必须写 COUNT(*)::numeric / COUNT(*) 或 *1.0，否则所有比率全是 0
-- 9) 视图、CTE、LAG、NTILE、窗口函数写法两边完全一致
-- 完整 PostgreSQL 版见 03_指标SQL_postgres.sql
