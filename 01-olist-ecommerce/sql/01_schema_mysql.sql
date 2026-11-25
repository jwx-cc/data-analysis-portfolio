-- =====================================================================
-- Olist 巴西电商订单数据集 · 建表 + 导入脚本（MySQL 8.0+）
-- 数据集：https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
-- 运行环境：MySQL 8.0 及以上（窗口函数 CTE 必须 8.0+，5.7 跑不了）
-- 编码：CSV 原始文件为 UTF-8，建库用 utf8mb4
-- 字段名保留原始拼写（含 product_name_lenght 等原始拼写错误，不要改，改了导入会失败）
-- =====================================================================

CREATE DATABASE IF NOT EXISTS olist
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

USE olist;

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. 客户表（99441 行）
-- customer_id       = 订单级 ID，每下一单生成一个新的，不能用来算复购
-- customer_unique_id= 客户级 ID，同一个人多次下单是同一个值，复购/留存必须用它
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
  customer_id              VARCHAR(64)  NOT NULL COMMENT '订单级客户ID（下单即新生成）',
  customer_unique_id       VARCHAR(64)  NOT NULL COMMENT '客户级唯一ID（算复购用它）',
  customer_zip_code_prefix VARCHAR(10)  NULL     COMMENT '邮编前5位',
  customer_city            VARCHAR(64)  NULL,
  customer_state           CHAR(2)      NULL     COMMENT '巴西州简称，如 SP/RJ/MG',
  PRIMARY KEY (customer_id),
  KEY idx_cuid (customer_unique_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='客户表';

-- ---------------------------------------------------------------------
-- 2. 订单主表（99441 行）
-- order_status 取值：delivered / shipped / canceled / unavailable /
--                    invoiced / processing / created / approved
-- 时间字段全部可能为 NULL（未支付/未发货/未签收）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
  order_id                       VARCHAR(64) NOT NULL,
  customer_id                    VARCHAR(64) NOT NULL,
  order_status                   VARCHAR(20) NULL,
  order_purchase_timestamp       DATETIME    NULL COMMENT '下单时间（做趋势用这个）',
  order_approved_at              DATETIME    NULL COMMENT '支付审核通过时间',
  order_delivered_carrier_date   DATETIME    NULL COMMENT '交给物流时间',
  order_delivered_customer_date  DATETIME    NULL COMMENT '客户签收时间',
  order_estimated_delivery_date  DATETIME    NULL COMMENT '承诺送达时间（算延迟用）',
  PRIMARY KEY (order_id),
  KEY idx_cust (customer_id),
  KEY idx_purchase (order_purchase_timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单主表';

-- ---------------------------------------------------------------------
-- 3. 订单商品明细表（112650 行）
-- 一个 order_id 可有多行（order_item_id 从 1 开始），SUM(price) 时不要重复算订单数
-- price 是商品金额，freight_value 是运费，GMV 口径默认只用 price
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS order_items;
CREATE TABLE order_items (
  order_id            VARCHAR(64)   NOT NULL,
  order_item_id       INT           NOT NULL COMMENT '同一订单内商品序号，从1开始',
  product_id          VARCHAR(64)   NOT NULL,
  seller_id           VARCHAR(64)   NOT NULL,
  shipping_limit_date DATETIME      NULL     COMMENT '卖家发货截止时间',
  price               DECIMAL(10,2) NULL     COMMENT '商品单价',
  freight_value       DECIMAL(10,2) NULL     COMMENT '运费',
  PRIMARY KEY (order_id, order_item_id),
  KEY idx_prod (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单商品明细';

-- ---------------------------------------------------------------------
-- 4. 支付表（103886 行）
-- 一个订单可能多行（分期/多张卡），算实收要用 SUM(payment_value)
-- payment_type：credit_card / boleto / voucher / debit_card / not_defined
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS order_payments;
CREATE TABLE order_payments (
  order_id             VARCHAR(64)   NOT NULL,
  payment_sequential   INT           NOT NULL COMMENT '支付序号',
  payment_type         VARCHAR(20)   NULL,
  payment_installments INT           NULL     COMMENT '分期数',
  payment_value        DECIMAL(10,2) NULL,
  PRIMARY KEY (order_id, payment_sequential)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单支付';

-- ---------------------------------------------------------------------
-- 5. 评价表（99224 行）
-- 注意：review_id 有重复（同一评价关联多订单），所以不要用 review_id 做主键，
--       这里用自增 id，这是真实业务里常见的数据质量问题，写进文档能加分
-- review_score：1-5 分，1-2 分视为差评
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS order_reviews;
CREATE TABLE order_reviews (
  id                      BIGINT AUTO_INCREMENT PRIMARY KEY,
  review_id               VARCHAR(64)  NULL,
  order_id                VARCHAR(64)  NULL,
  review_score            TINYINT      NULL,
  review_comment_title    VARCHAR(255) NULL,
  review_comment_message  TEXT         NULL,
  review_creation_date    DATETIME     NULL,
  review_answer_timestamp DATETIME     NULL,
  KEY idx_order (order_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单评价';

-- ---------------------------------------------------------------------
-- 6. 商品表（32951 行）
-- product_category_name 为葡语，需 JOIN 翻译表取英文品类
-- 注意字段名原始拼写就是 lenght（不是 length）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS products;
CREATE TABLE products (
  product_id                 VARCHAR(64) NOT NULL,
  product_category_name      VARCHAR(100) NULL COMMENT '葡语品类名，可能为NULL',
  product_name_lenght        INT NULL,
  product_description_lenght INT NULL,
  product_photos_qty         INT NULL,
  product_weight_g           INT NULL,
  product_length_cm          INT NULL,
  product_height_cm          INT NULL,
  product_width_cm           INT NULL,
  PRIMARY KEY (product_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='商品表';

-- ---------------------------------------------------------------------
-- 7. 卖家表（3095 行）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sellers;
CREATE TABLE sellers (
  seller_id              VARCHAR(64) NOT NULL,
  seller_zip_code_prefix VARCHAR(10) NULL,
  seller_city            VARCHAR(64) NULL,
  seller_state           CHAR(2)     NULL,
  PRIMARY KEY (seller_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='卖家表';

-- ---------------------------------------------------------------------
-- 8. 地理位置表（1000163 行，1M 行，本项目用不到，可以最后再导）
-- 同一邮编前缀有多条经纬度，不能设主键
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS geolocation;
CREATE TABLE geolocation (
  geolocation_zip_code_prefix VARCHAR(10) NULL,
  geolocation_lat             DECIMAL(12,8) NULL,
  geolocation_lng             DECIMAL(12,8) NULL,
  geolocation_city            VARCHAR(64) NULL,
  geolocation_state           CHAR(2) NULL,
  KEY idx_zip (geolocation_zip_code_prefix)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='邮编地理位置';

-- ---------------------------------------------------------------------
-- 9. 品类翻译表（71 行）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS product_category_name_translation;
CREATE TABLE product_category_name_translation (
  product_category_name         VARCHAR(100) NOT NULL,
  product_category_name_english VARCHAR(100) NULL,
  PRIMARY KEY (product_category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='品类葡语-英语对照';

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- 导入数据（二选一）
-- =====================================================================
-- 方式 A：命令行 LOAD DATA（最快，推荐）
-- MySQL 8 默认关闭 local_infile，先执行：
--   SET GLOBAL local_infile = 1;
-- 客户端连接时也要带参数：mysql --local-infile=1 -u root -p
-- 然后把下面的路径改成你解压后的实际路径（Windows 用正斜杠或双反斜杠）
--
-- LOAD DATA LOCAL INFILE '/path/olist_customers_dataset.csv'
-- INTO TABLE customers FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
--
-- LOAD DATA LOCAL INFILE '/path/olist_orders_dataset.csv'
-- INTO TABLE orders FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
--
-- LOAD DATA LOCAL INFILE '/path/olist_order_items_dataset.csv'
-- INTO TABLE order_items FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
--
-- LOAD DATA LOCAL INFILE '/path/olist_order_payments_dataset.csv'
-- INTO TABLE order_payments FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
--
-- LOAD DATA LOCAL INFILE '/path/olist_order_reviews_dataset.csv'
-- INTO TABLE order_reviews FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES
-- (@review_id,@order_id,@review_score,@title,@msg,@create,@answer)
-- SET review_id=@review_id, order_id=@order_id, review_score=@review_score,
--     review_comment_title=@title, review_comment_message=@msg,
--     review_creation_date=@create, review_answer_timestamp=@answer;
--   ↑ 评价表含长文本+换行，必须显式指定列，否则会串行
--
-- LOAD DATA LOCAL INFILE '/path/olist_products_dataset.csv'
-- INTO TABLE products FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
--
-- LOAD DATA LOCAL INFILE '/path/olist_sellers_dataset.csv'
-- INTO TABLE sellers FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
--
-- LOAD DATA LOCAL INFILE '/path/product_category_name_translation.csv'
-- INTO TABLE product_category_name_translation FIELDS TERMINATED BY ',' ENCLOSED BY '"'
-- LINES TERMINATED BY '\n' IGNORE 1 LINES;
--
-- 方式 B：图形界面导入向导（Navicat / MySQL Workbench / DBeaver）
-- 右键表 > 导入向导 > CSV > 编码选 UTF-8 > 第一行是标题 > 直接下一步
-- 注意：orders 表的 5 个时间列要手动确认成 DATETIME，否则会导成字符串，
--       后面 DATE_FORMAT / DATEDIFF 全部报错
-- =====================================================================

-- 导入后必做的行数核对（数字必须对得上，对不上就是导入断了）
-- 期望值：customers 99441 / orders 99441 / order_items 112650 /
--         order_payments 103886 / order_reviews 99224 / products 32951 /
--         sellers 3095 / translation 71
SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM customers
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL SELECT 'translation', COUNT(*) FROM product_category_name_translation;
