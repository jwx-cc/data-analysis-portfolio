-- =====================================================================
-- MySQL 8.0 新实例 · 一次性重导 8 张表
-- 前置：先在新实例里完整跑一遍 01_建表_olist_mysql.sql（建库 + 建表）
-- 路径：D:/olist/  如果你的解压目录不同，全局替换这个前缀
-- 用法：在 Navicat 查询窗口里，从上往下逐段执行（不要一次全选）
-- =====================================================================

USE olist;

-- 关闭严格模式：products 表有 2 行数值字段为空字符串，严格模式下会报
-- ERROR 1366 Incorrect integer value: ''
SET SESSION sql_mode = '';

-- ---------------------------------------------------------------------
-- 1. customers（5 列，无空值，直接导）
-- ---------------------------------------------------------------------
TRUNCATE TABLE customers;
LOAD DATA LOCAL INFILE 'D:/olist/olist_customers_dataset.csv'
INTO TABLE customers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- 2. orders（8 列，5 个时间列有空值，必须 NULLIF 兜住）
-- ---------------------------------------------------------------------
TRUNCATE TABLE orders;
LOAD DATA LOCAL INFILE 'D:/olist/olist_orders_dataset.csv'
INTO TABLE orders
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES
(@order_id,@customer_id,@status,@purchase,@approved,@carrier,@delivered,@estimated)
SET order_id                      = @order_id,
    customer_id                   = @customer_id,
    order_status                  = @status,
    order_purchase_timestamp      = NULLIF(@purchase, ''),
    order_approved_at             = NULLIF(@approved, ''),
    order_delivered_carrier_date  = NULLIF(@carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered, ''),
    order_estimated_delivery_date = NULLIF(@estimated, '');

-- ---------------------------------------------------------------------
-- 3. order_items（7 列）
-- ---------------------------------------------------------------------
TRUNCATE TABLE order_items;
LOAD DATA LOCAL INFILE 'D:/olist/olist_order_items_dataset.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- 4. order_payments（5 列）
-- ---------------------------------------------------------------------
TRUNCATE TABLE order_payments;
LOAD DATA LOCAL INFILE 'D:/olist/olist_order_payments_dataset.csv'
INTO TABLE order_payments
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- 5. order_reviews（7 列，含长文本 + 内嵌换行 + 两个时间列空值）
-- 注意：这张表可能少 1 行（99223 而非 99224），属已知边界问题，可接受
-- ---------------------------------------------------------------------
TRUNCATE TABLE order_reviews;
LOAD DATA LOCAL INFILE 'D:/olist/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES
(@review_id,@order_id,@review_score,@title,@msg,@create,@answer)
SET review_id               = @review_id,
    order_id                = @order_id,
    review_score            = NULLIF(@review_score, ''),
    review_comment_title    = @title,
    review_comment_message  = @msg,
    review_creation_date    = NULLIF(@create, ''),
    review_answer_timestamp = NULLIF(@answer, '');

-- ---------------------------------------------------------------------
-- 6. products（9 列，品类和 4 个尺寸/重量字段都可能为空）
-- ---------------------------------------------------------------------
TRUNCATE TABLE products;
LOAD DATA LOCAL INFILE 'D:/olist/olist_products_dataset.csv'
INTO TABLE products
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES
(@product_id,@cat,@name_len,@desc_len,@photos,@weight,@l_cm,@h_cm,@w_cm)
SET product_id                 = @product_id,
    product_category_name      = NULLIF(@cat, ''),
    product_name_lenght        = NULLIF(@name_len, ''),
    product_description_lenght = NULLIF(@desc_len, ''),
    product_photos_qty         = NULLIF(@photos, ''),
    product_weight_g           = NULLIF(@weight, ''),
    product_length_cm          = NULLIF(@l_cm, ''),
    product_height_cm          = NULLIF(@h_cm, ''),
    product_width_cm           = NULLIF(@w_cm, '');

-- ---------------------------------------------------------------------
-- 7. sellers（4 列）
-- ---------------------------------------------------------------------
TRUNCATE TABLE sellers;
LOAD DATA LOCAL INFILE 'D:/olist/olist_sellers_dataset.csv'
INTO TABLE sellers
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- ---------------------------------------------------------------------
-- 8. product_category_name_translation（2 列）
-- ---------------------------------------------------------------------
TRUNCATE TABLE product_category_name_translation;
LOAD DATA LOCAL INFILE 'D:/olist/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n' IGNORE 1 LINES;

-- =====================================================================
-- 导入后核对：期望值 99441 / 99441 / 112650 / 103886 / 99223 / 32951 / 3095 / 71
-- =====================================================================
SELECT 'customers' AS tbl, COUNT(*) AS cnt FROM customers
UNION ALL SELECT 'orders',            COUNT(*) FROM orders
UNION ALL SELECT 'order_items',       COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments',    COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',     COUNT(*) FROM order_reviews
UNION ALL SELECT 'products',          COUNT(*) FROM products
UNION ALL SELECT 'sellers',           COUNT(*) FROM sellers
UNION ALL SELECT 'translation',       COUNT(*) FROM product_category_name_translation;

-- 时间列没有被误伤成 0 值（必须返回 0）
SELECT COUNT(*) AS null_purchase_ts FROM orders WHERE order_purchase_timestamp IS NULL;
