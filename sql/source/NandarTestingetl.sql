-- =====================================================================
-- HOMEWORK: WATERMARK incremental load of order_items (raw -> staging)
-- Same pattern as staging.load_orders_incremental() in 04_watermark_log_dq.sql
--
-- Watermark column : shipping_limit_date  (etl_control row 'order_items')
-- Business key     : (order_id, order_item_id)  -- composite
-- Derived column   : total_value = price + freight_value
-- Reject key       : order_id || '-' || order_item_id
-- Prerequisite     : staging.orders and staging.products are loaded,
--                    staging.etl_control / etl_log / rejected_rows exist
--                    (run 04_watermark_log_dq.sql first)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. TARGET TABLE (create once; adds total_value + updated_at)
--    If staging.order_items already exists from
--    01_raw_to_staging_procedures.sql with `total_amount`, use the ALTERs.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.order_items (
    order_id           TEXT          NOT NULL,
    order_item_id      INT           NOT NULL,
    product_id         TEXT,
    seller_id          TEXT,
    shipping_limit_ts  TIMESTAMP,
    price              NUMERIC(10,2),
    freight_value      NUMERIC(10,2),
    total_value        NUMERIC(10,2),
    updated_at         TIMESTAMP,
    PRIMARY KEY (order_id, order_item_id)
);

ALTER TABLE staging.order_items ADD COLUMN IF NOT EXISTS total_value NUMERIC(10,2);
ALTER TABLE staging.order_items ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP;

-- ---------------------------------------------------------------------
-- 1. PROCEDURE: incremental load with watermark + DQ + logging
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE staging.load_order_items_incremental()
LANGUAGE plpgsql AS $$
DECLARE
    v_run_id    UUID := gen_random_uuid();
    v_log_id    BIGINT;
    v_wm_from   TIMESTAMP;
    v_wm_to     TIMESTAMP;
    v_read      INT := 0;
    v_rejected  INT := 0;
    v_loaded    INT := 0;
BEGIN
    -- TODO 1: control row + read watermark
    INSERT INTO staging.etl_control (table_name) VALUES ('order_items')
    ON CONFLICT (table_name) DO NOTHING;

    SELECT last_loaded_ts INTO v_wm_from
    FROM staging.etl_control WHERE table_name = 'order_items';

    -- log start (outside the exception block)
    INSERT INTO staging.etl_log (run_id, step_name, started_at, status, watermark_from)
    VALUES (v_run_id, 'load_order_items_incremental', clock_timestamp(), 'RUNNING', v_wm_from)
    RETURNING log_id INTO v_log_id;

    BEGIN
        DROP TABLE IF EXISTS tmp_order_items_delta;
        CREATE TEMP TABLE tmp_order_items_delta AS
        SELECT d.*,
               CASE
                   -- TODO 2: the 5 DQ rules, in priority order
                   WHEN d.order_id IS NULL OR d.order_item_id IS NULL
                        THEN 'NULL_KEY'
                   WHEN d.price IS NULL OR d.price <= 0
                        THEN 'INVALID_PRICE'
                   WHEN d.freight_value < 0
                        THEN 'NEGATIVE_FREIGHT'
                   WHEN NOT EXISTS (SELECT 1 FROM staging.orders o
                                    WHERE o.order_id = d.order_id)
                        THEN 'ORPHAN_ORDER'
                   WHEN NOT EXISTS (SELECT 1 FROM staging.products p
                                    WHERE p.product_id = d.product_id)
                        THEN 'ORPHAN_PRODUCT'
               END AS dq_reason
        FROM (
            SELECT DISTINCT ON (order_id, order_item_id)
                   order_id,
                   order_item_id::INT                              AS order_item_id,
                   product_id,
                   seller_id,
                   NULLIF(shipping_limit_date::TEXT, '')::TIMESTAMP AS shipping_limit_ts,
                   NULLIF(price::TEXT, '')::NUMERIC(10,2)           AS price,
                   NULLIF(freight_value::TEXT, '')::NUMERIC(10,2)   AS freight_value,
                   -- TODO 3: derived column total_value
                   NULLIF(price::TEXT, '')::NUMERIC(10,2)
                     + NULLIF(freight_value::TEXT, '')::NUMERIC(10,2) AS total_value
            FROM raw.order_items
            -- TODO 4: the incremental filter
            WHERE NULLIF(shipping_limit_date::TEXT, '')::TIMESTAMP > v_wm_from
            ORDER BY order_id, order_item_id, shipping_limit_date DESC
        ) d;

        -- TODO 5: count rows into v_read and v_rejected
        SELECT COUNT(*), COUNT(*) FILTER (WHERE dq_reason IS NOT NULL)
        INTO v_read, v_rejected
        FROM tmp_order_items_delta;

        -- TODO 6: insert rejected rows into staging.rejected_rows
        INSERT INTO staging.rejected_rows (run_id, table_name, business_key, reason, row_data)
        SELECT v_run_id, 'order_items',
               order_id || '-' || order_item_id,
               dq_reason, to_jsonb(t) - 'dq_reason'
        FROM tmp_order_items_delta t
        WHERE dq_reason IS NOT NULL;

        -- TODO 7: upsert clean rows into staging.order_items
        INSERT INTO staging.order_items AS t
               (order_id, order_item_id, product_id, seller_id,
                shipping_limit_ts, price, freight_value, total_value, updated_at)
        SELECT order_id, order_item_id, product_id, seller_id,
               shipping_limit_ts, price, freight_value, total_value, now()
        FROM tmp_order_items_delta
        WHERE dq_reason IS NULL
        ON CONFLICT (order_id, order_item_id) DO UPDATE
        SET product_id        = EXCLUDED.product_id,
            seller_id         = EXCLUDED.seller_id,
            shipping_limit_ts = EXCLUDED.shipping_limit_ts,
            price             = EXCLUDED.price,
            freight_value     = EXCLUDED.freight_value,
            total_value       = EXCLUDED.total_value,
            updated_at        = now();
        GET DIAGNOSTICS v_loaded = ROW_COUNT;

        -- TODO 8: move the watermark forward (only if rows were read)
        SELECT MAX(shipping_limit_ts) INTO v_wm_to FROM tmp_order_items_delta;
        IF v_wm_to IS NOT NULL THEN
            UPDATE staging.etl_control
            SET last_loaded_ts = v_wm_to
            WHERE table_name = 'order_items';
        ELSE
            v_wm_to := v_wm_from;
        END IF;

        UPDATE staging.etl_log
        SET status = 'SUCCESS', finished_at = clock_timestamp(),
            rows_read = v_read, rows_loaded = v_loaded, rows_rejected = v_rejected,
            watermark_to = v_wm_to
        WHERE log_id = v_log_id;

        RAISE NOTICE 'order_items incremental: read %, loaded %, rejected %, watermark % -> %',
                     v_read, v_loaded, v_rejected, v_wm_from, v_wm_to;

    EXCEPTION WHEN OTHERS THEN
        -- TODO 9: mark the log row FAILED with SQLERRM, then RAISE WARNING
        UPDATE staging.etl_log
        SET status = 'FAILED', finished_at = clock_timestamp(), message = SQLERRM
        WHERE log_id = v_log_id;
        RAISE WARNING 'load_order_items_incremental FAILED: %', SQLERRM;
    END;
END $$;

-- ---------------------------------------------------------------------
-- 2. DEMO / TEST
-- ---------------------------------------------------------------------
-- Backup the watermark before testing
--   CREATE TABLE IF NOT EXISTS staging.etl_control_backup AS
--       SELECT * FROM staging.etl_control WHERE table_name = 'order_items';
--
-- Run 1: watermark is 1900-01-01, everything is loaded
--   CALL staging.load_order_items_incremental();
--
-- Run 2: nothing new -> read 0, loaded 0
--   CALL staging.load_order_items_incremental();
--
-- Test rows (order_item_id >= 900, shipping_limit_date in 2030):
--   good row needs a real order_id + product_id from staging
--   INSERT INTO raw.order_items (order_id, order_item_id, product_id, seller_id,
--                                shipping_limit_date, price, freight_value)
--   VALUES
--     ((SELECT order_id FROM staging.orders LIMIT 1), 900,
--      (SELECT product_id FROM staging.products LIMIT 1),
--      (SELECT seller_id FROM staging.order_items LIMIT 1),
--      '2030-01-10 10:00:00', '100.00', '10.00'),              -- clean: loaded, total_value = 110
--     (NULL, 901, 'x', 'x', '2030-01-10 10:00:00', '10', '1'),-- NULL_KEY
--     ('missing_order', 902, 'x', 'x', '2030-01-10 10:00:00', '0', '1'),   -- INVALID_PRICE
--     ('missing_order', 903, 'x', 'x', '2030-01-10 10:00:00', '10', '-1'), -- NEGATIVE_FREIGHT
--     ('missing_order', 904, 'x', 'x', '2030-01-10 10:00:00', '10', '1'),  -- ORPHAN_ORDER
--     ((SELECT order_id FROM staging.orders LIMIT 1), 905,
--      'missing_product', 'x', '2030-01-10 10:00:00', '10', '1'),          -- ORPHAN_PRODUCT
--     -- duplicate key: the later shipping_limit_date wins
--     ((SELECT order_id FROM staging.orders LIMIT 1), 906,
--      (SELECT product_id FROM staging.products LIMIT 1), 'x',
--      '2030-01-10 10:00:00', '50.00', '5.00'),
--     ((SELECT order_id FROM staging.orders LIMIT 1), 906,
--      (SELECT product_id FROM staging.products LIMIT 1), 'x',
--      '2030-01-11 10:00:00', '60.00', '6.00');
--   CALL staging.load_order_items_incremental();   -- read 7, loaded 2, rejected 5
--
-- Invariant after every run: rows_read = rows_loaded + rows_rejected
--   SELECT * FROM staging.etl_log ORDER BY log_id DESC LIMIT 2;
--   SELECT business_key, reason FROM staging.rejected_rows ORDER BY reject_id DESC;
--
-- Clean up + restore the watermark
--   DELETE FROM raw.order_items WHERE order_item_id::INT >= 900;
--   DELETE FROM staging.order_items WHERE order_item_id >= 900;
--   DELETE FROM staging.rejected_rows WHERE table_name = 'order_items';
--   UPDATE staging.etl_control c SET last_loaded_ts = b.last_loaded_ts
--   FROM staging.etl_control_backup b
--   WHERE c.table_name = b.table_name AND c.table_name = 'order_items';
