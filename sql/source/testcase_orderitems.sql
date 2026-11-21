-- =====================================================================
-- TEST SCRIPT for staging.load_order_items_incremental()
-- Run top to bottom, one section at a time, and read the NOTICE/output
-- after each step. Every test row uses order_item_id >= 900 and a
-- shipping_limit_date in 2030 so it is always above the watermark.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 0: backup the watermark (so we can restore it at the end)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS staging.etl_control_backup;
CREATE TABLE staging.etl_control_backup AS
    SELECT * FROM staging.etl_control WHERE table_name = 'order_items';

SELECT * FROM staging.etl_control_backup;   -- remember last_loaded_ts


-- ---------------------------------------------------------------------
-- STEP 1: insert test rows into raw.order_items
--   900 = clean row             -> loaded, total_value = 110.00
--   902 = price 0               -> INVALID_PRICE
--   903 = freight -1            -> NEGATIVE_FREIGHT
--   904 = order not in staging  -> ORPHAN_ORDER
--   905 = product not in staging-> ORPHAN_PRODUCT
--   906 = duplicate key x2      -> only the LATER shipping_limit_date wins
--
-- NOTE on NULL_KEY: raw.order_items.order_id is NOT NULL, so a NULL key
-- can never reach the procedure — the rule exists only as a safety net.
-- NOTE on duplicates: raw.order_items has PRIMARY KEY (order_id,
-- order_item_id), so we drop the PK for a moment to insert two rows
-- with the same key, then put the constraint back at cleanup.
-- NOTE on orphans: raw.order_items has FKs to raw.orders/products/
-- sellers, so a fake parent must first exist in RAW (but NOT in
-- staging) — the DQ check looks at staging, so it still fires.
-- ---------------------------------------------------------------------
ALTER TABLE raw.order_items DROP CONSTRAINT order_items_pkey;

-- fake parents that exist only in raw -> orphan vs staging
INSERT INTO raw.order_items
       (order_id, order_item_id, product_id, seller_id,
        shipping_limit_date, price, freight_value)
VALUES
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 900,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '100.00', '10.00'),
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 902,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '0.00', '1.00'),
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 903,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '10.00', '-1.00'),
    ('missing_order', 904,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '10.00', '1.00'),
    ((SELECT order_id FROM staging.orders LIMIT 1), 905,
     'missing_product',
     (SELECT seller_id FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '10.00', '1.00'),
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 906,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '50.00', '5.00'),
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 906,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-11 10:00:00', '60.00', '6.00');


-- ---------------------------------------------------------------------
-- STEP 2: run the procedure
--   Expect NOTICE: read 6, loaded 2, rejected 4
--   (rows_read = rows_loaded + rows_rejected  ->  6 = 2 + 4)
-- ---------------------------------------------------------------------
CALL staging.load_order_items_incremental();

-- check the log row  -> SCREENSHOT 1: staging.etl_log
SELECT log_id, step_name, status, rows_read, rows_loaded, rows_rejected,
       watermark_from, watermark_to
FROM staging.etl_log
ORDER BY log_id DESC LIMIT 1;


-- ---------------------------------------------------------------------
-- STEP 3: verify the clean rows landed correctly
--   900: total_value = 110.00
--   906: ONE row only, shipping_limit_ts = 2030-01-11, total_value = 66.00
-- ---------------------------------------------------------------------
SELECT order_id, order_item_id, shipping_limit_ts, price, freight_value, total_value
FROM staging.order_items
WHERE order_item_id IN (900, 906);


-- ---------------------------------------------------------------------
-- STEP 4: verify each DQ rule rejected the right row
--   -> SCREENSHOT 2: staging.rejected_rows
--   Expect 4 rows: INVALID_PRICE(902), NEGATIVE_FREIGHT(903),
--                  ORPHAN_ORDER(904), ORPHAN_PRODUCT(905)
-- ---------------------------------------------------------------------
SELECT business_key, reason
FROM staging.rejected_rows
WHERE table_name = 'order_items'
ORDER BY reject_id DESC LIMIT 10;


-- ---------------------------------------------------------------------
-- STEP 5: second run reads 0 rows (incremental proof)
--   Expect NOTICE: read 0, loaded 0, rejected 0
-- ---------------------------------------------------------------------
CALL staging.load_order_items_incremental();

SELECT status, rows_read, rows_loaded, rows_rejected
FROM staging.etl_log
ORDER BY log_id DESC LIMIT 1;   -- read 0, loaded 0, rejected 0


-- ---------------------------------------------------------------------
-- STEP 6: forced failure -> log shows FAILED and watermark does NOT move
--   We break the run by renaming a column the procedure SELECTs:
--   the temp-table CREATE fails ("column does not exist"), the
--   EXCEPTION block logs FAILED, and the block's changes (incl. the
--   watermark) roll back. Then we put the column back.
-- ---------------------------------------------------------------------
SELECT last_loaded_ts AS wm_before_failure
FROM staging.etl_control WHERE table_name = 'order_items';

-- insert one more clean raw row so there is something to fail on
INSERT INTO raw.order_items
       (order_id, order_item_id, product_id, seller_id,
        shipping_limit_date, price, freight_value)
VALUES ((SELECT order_id   FROM staging.orders   LIMIT 1), 907,
        (SELECT product_id FROM staging.products LIMIT 1),
        (SELECT seller_id  FROM staging.order_items LIMIT 1),
        '2030-01-12 10:00:00', '10.00', '1.00');

ALTER TABLE raw.order_items RENAME COLUMN price TO price_tmp;   -- break it

CALL staging.load_order_items_incremental();   -- WARNING: FAILED: column ... does not exist

SELECT status, message
FROM staging.etl_log
ORDER BY log_id DESC LIMIT 1;                  -- status = FAILED

-- watermark unchanged: still the same value as wm_before_failure
SELECT last_loaded_ts AS wm_after_failure
FROM staging.etl_control WHERE table_name = 'order_items';

ALTER TABLE raw.order_items RENAME COLUMN price_tmp TO price;   -- fix it


-- ---------------------------------------------------------------------
-- STEP 7: clean up test rows and restore the original watermark
-- ---------------------------------------------------------------------
DELETE FROM raw.order_items    WHERE order_item_id >= 900;
DELETE FROM staging.order_items WHERE order_item_id >= 900;
DELETE FROM staging.rejected_rows WHERE table_name = 'order_items';

-- remove the fake raw-only parents
DELETE FROM raw.orders   WHERE order_id   = 'missing_order';
DELETE FROM raw.products WHERE product_id = 'missing_product';

-- restore the raw PK that was dropped in STEP 1 (test rows must be
-- deleted first, or the PK re-creation fails on the 906 duplicate)
ALTER TABLE raw.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (order_id, order_item_id);

UPDATE staging.etl_control c
SET last_loaded_ts = b.last_loaded_ts
FROM staging.etl_control_backup b
WHERE c.table_name = b.table_name
  AND c.table_name = 'order_items';

DROP TABLE staging.etl_control_backup;

-- final sanity check
SELECT * FROM staging.etl_control;
SELECT COUNT(*) FROM staging.order_items WHERE order_item_id >= 900;  -- 0
