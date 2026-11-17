
SELECT * FROM staging.etl_control;

UPDATE staging.etl_control
SET last_loaded_ts = '1900-01-01 00:00:00'
WHERE table_name = 'order_items';

-- alternative to the UPDATE: delete the control row entirely.
-- The procedure re-creates it with the default 1900-01-01 on next run.
-- Use ONE of them, not both.
-- DELETE FROM staging.etl_control WHERE table_name = 'order_items';

TRUNCATE TABLE staging.order_items;

-- verify the reset
SELECT last_loaded_ts
FROM staging.etl_control
WHERE table_name = 'order_items';                    -- expect 1900-01-01

SELECT * FROM staging.etl_log ORDER BY log_id DESC LIMIT 5;

SELECT COUNT(*) FROM raw.order_items;                -- expect 112650
SELECT COUNT(*) FROM staging.order_items;            -- expect 0


-- =====================================================================
-- STEP 1: FIRST CALL = FULL LOAD
--   expect: read 112650, loaded 112650, rejected 0
--           watermark 1900-01-01 -> max real shipping_limit_date (~2020)
-- =====================================================================
CALL staging.load_order_items_incremental();

-- check the log row
SELECT log_id, step_name, status, rows_read, rows_loaded, rows_rejected,
       watermark_from, watermark_to
FROM staging.etl_log
ORDER BY log_id DESC LIMIT 1;

SELECT COUNT(*) FROM staging.order_items;            -- expect 112650


-- =====================================================================
-- STEP 2: CREATE FAKE PARENTS (raw only, NOT in staging)
--   raw.order_items has foreign keys to raw.orders / raw.products, so
--   the parents must exist in raw. They must NOT exist in staging,
--   because the DQ rules check staging -> ORPHAN_ORDER / ORPHAN_PRODUCT.
-- =====================================================================
INSERT INTO raw.orders (order_id, customer_id, order_status, order_purchase_timestamp)
VALUES ('missing_order',
        (SELECT customer_id FROM raw.customers LIMIT 1),
        'delivered', TIMESTAMP '2030-01-01 10:00:00')
ON CONFLICT (order_id) DO NOTHING;

INSERT INTO raw.products (product_id)
VALUES ('missing_product')
ON CONFLICT (product_id) DO NOTHING;

-- verify: raw has them, staging does NOT
SELECT order_id   FROM raw.orders       WHERE order_id   = 'missing_order';     -- 1 row
SELECT product_id FROM raw.products     WHERE product_id = 'missing_product';   -- 1 row
SELECT product_id FROM staging.products WHERE product_id = 'missing_product';   -- 0 rows


-- =====================================================================
-- STEP 3: RELAX RAW CONSTRAINTS (restored in STEP 9)
--   DROP the primary key -> allows the duplicate key (906)
--   DROP NOT NULL        -> allows the NULL key (901)
-- =====================================================================
ALTER TABLE raw.order_items DROP CONSTRAINT order_items_pkey;
ALTER TABLE raw.order_items ALTER COLUMN order_id DROP NOT NULL;

-- verify order_id now accepts NULL (attnotnull = false)
SELECT attname, attnotnull
FROM pg_attribute
WHERE attrelid = 'raw.order_items'::regclass
  AND attname IN ('order_id', 'order_item_id');


-- =====================================================================
-- STEP 4: INSERT TEST ROWS
--   900 = clean row               -> loaded, total_value = 110.00
--   901 = NULL order_id           -> NULL_KEY
--   902 = price 0                 -> INVALID_PRICE
--   903 = freight -1              -> NEGATIVE_FREIGHT
--   904 = order missing in staging-> ORPHAN_ORDER
--   905 = product missing staging -> ORPHAN_PRODUCT
--   906 = duplicate key x2        -> only the LATER shipping_limit_date wins
-- =====================================================================
INSERT INTO raw.order_items
       (order_id, order_item_id, product_id, seller_id,
        shipping_limit_date, price, freight_value)
VALUES
    -- 900: clean row, all parents real
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 900,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '100.00', '10.00'),

    -- 901: NULL business key -> NULL_KEY
    (NULL, 901,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '10.00', '1.00'),

    -- 902: price = 0 -> INVALID_PRICE
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 902,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '0.00', '1.00'),

    -- 903: freight < 0 -> NEGATIVE_FREIGHT
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 903,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '10.00', '-1.00'),

    -- 904: parent order only in raw -> ORPHAN_ORDER
    ('missing_order', 904,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '10.00', '1.00'),

    -- 905: parent product only in raw -> ORPHAN_PRODUCT
    ((SELECT order_id FROM staging.orders LIMIT 1), 905,
     'missing_product',
     (SELECT seller_id FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '10.00', '1.00'),

    -- 906: same key twice; the 2030-01-11 version must win
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 906,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-10 10:00:00', '50.00', '5.00'),
    ((SELECT order_id   FROM staging.orders   LIMIT 1), 906,
     (SELECT product_id FROM staging.products LIMIT 1),
     (SELECT seller_id  FROM staging.order_items LIMIT 1),
     '2030-01-11 10:00:00', '60.00', '6.00');

-- 8 raw test rows inserted (7 unique business keys)
SELECT COUNT(*) FROM raw.order_items WHERE order_item_id >= 900;   -- expect 8


-- =====================================================================
-- STEP 5: RUN THE PROCEDURE
--   expect: read 7, loaded 2, rejected 5   (7 = 2 + 5)
--           watermark_to = 2030-01-11 10:00:00
-- =====================================================================
CALL staging.load_order_items_incremental();

SELECT log_id, step_name, status, rows_read, rows_loaded, rows_rejected,
       watermark_from, watermark_to
FROM staging.etl_log
ORDER BY log_id DESC LIMIT 1;


-- =====================================================================
-- STEP 6: VERIFY THE LOADED ROWS
--   900: total_value = 110.00 (100 + 10)
--   906: exactly ONE row, the 2030-01-11 version, total_value = 66.00
-- =====================================================================
SELECT order_id, order_item_id, shipping_limit_ts,
       price, freight_value, total_value
FROM staging.order_items
WHERE order_item_id IN (900, 906);


-- =====================================================================
-- STEP 7: VERIFY THE REJECTED ROWS
--   expect 5 reasons:
--     901 NULL_KEY   (business_key is NULL because order_id is NULL)
--     902 INVALID_PRICE
--     903 NEGATIVE_FREIGHT
--     904 ORPHAN_ORDER
--     905 ORPHAN_PRODUCT
-- =====================================================================
SELECT business_key, reason, row_data->>'order_item_id' AS order_item_id
FROM staging.rejected_rows
WHERE table_name = 'order_items'
ORDER BY reject_id DESC LIMIT 10;


-- =====================================================================
-- STEP 8: SECOND RUN = 0 ROWS (incremental proof)
--   The watermark is now 2030-01-11; nothing newer exists.
--   expect: read 0, loaded 0, rejected 0
-- =====================================================================
CALL staging.load_order_items_incremental();

SELECT status, rows_read, rows_loaded, rows_rejected
FROM staging.etl_log
ORDER BY log_id DESC LIMIT 1;


-- =====================================================================
-- STEP 9: FORCED FAILURE -> FAILED logged, watermark does NOT move
--   Rename the 'price' column the procedure selects, so the query
--   fails with "column does not exist".
--
--   IMPORTANT: do NOT call the procedure again after renaming the
--   column back, or item 907 loads and the watermark moves to
--   2030-01-12 (correct behaviour, but hides the failure test).
-- =====================================================================
SELECT last_loaded_ts AS wm_before_failure
FROM staging.etl_control WHERE table_name = 'order_items';   -- expect 2030-01-11

-- one more clean row, dated AFTER the current watermark
INSERT INTO raw.order_items
       (order_id, order_item_id, product_id, seller_id,
        shipping_limit_date, price, freight_value)
VALUES ((SELECT order_id   FROM staging.orders   LIMIT 1), 907,
        (SELECT product_id FROM staging.products LIMIT 1),
        (SELECT seller_id  FROM staging.order_items LIMIT 1),
        '2030-01-12 10:00:00', '10.00', '1.00');

ALTER TABLE raw.order_items RENAME COLUMN price TO price_tmp;   -- break it

CALL staging.load_order_items_incremental();   -- WARNING: FAILED: column "price" does not exist

SELECT status, message
FROM staging.etl_log
ORDER BY log_id DESC LIMIT 1;                  -- expect status = FAILED

-- the watermark must still equal wm_before_failure (2030-01-11)
SELECT last_loaded_ts AS wm_after_failure
FROM staging.etl_control WHERE table_name = 'order_items';

ALTER TABLE raw.order_items RENAME COLUMN price_tmp TO price;   -- fix it


-- =====================================================================
-- STEP 10: CLEAN UP TEST DATA
--   
--   Order matters: item rows first, then the fake parents.
-- =====================================================================
DELETE FROM raw.order_items     WHERE order_item_id >= 900;
DELETE FROM staging.order_items WHERE order_item_id >= 900;

-- remove only the rejects created by THIS test
DELETE FROM staging.rejected_rows
WHERE table_name = 'order_items'
  AND (business_key IS NULL
       OR (row_data->>'order_item_id')::INT >= 900);

-- remove the fake raw-only parents
DELETE FROM raw.orders   WHERE order_id   = 'missing_order';
DELETE FROM raw.products WHERE product_id = 'missing_product';


-- =====================================================================
-- STEP 11: RESTORE CONSTRAINTS AND WATERMARK
-- =====================================================================
-- the NULL-key row must be gone BEFORE these run
DELETE FROM raw.order_items WHERE order_id IS NULL;

ALTER TABLE raw.order_items ALTER COLUMN order_id SET NOT NULL;

ALTER TABLE raw.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (order_id, order_item_id);




-- =====================================================================
-- STEP 12: FINAL CHECKS
-- =====================================================================
SELECT * FROM staging.etl_control;                                  -- watermark back to ~2020
SELECT COUNT(*) FROM raw.order_items     WHERE order_item_id >= 900; -- 0
SELECT COUNT(*) FROM staging.order_items WHERE order_item_id >= 900; -- 0
SELECT COUNT(*) FROM staging.order_items;                            -- 112650

SELECT conname
FROM pg_constraint
WHERE conrelid = 'raw.order_items'::regclass AND contype = 'p';      -- order_items_pkey restored
