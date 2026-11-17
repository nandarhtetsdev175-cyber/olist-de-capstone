"""
Week 5 demo + Week 7: a small ETL pipeline with Python + Pandas + an API.

Extract   -> read the raw Olist orders + order items CSVs,
             and get today's BRL -> USD rate from the exchange-rate API
Transform -> clean text, convert types, check quality, rename, add columns
             (order total in BRL, the rate, and the total in USD)
Load      -> upsert into Postgres (staging.stg_orders), one row per order_id

Run (from the project root):
    source .venv/bin/activate          (Mac/Linux)  |  .venv\\Scripts\\activate  (Windows)
    pip install -r requirements.txt
    python scripts/ETL_final_test.py

Running it again is safe: existing orders are updated, never duplicated.
"""

import logging
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from urllib.parse import quote_plus

import pandas as pd
import requests
from dotenv import load_dotenv
from sqlalchemy import create_engine, text

# ---------- Config ----------
BASE_DIR = Path(__file__).resolve().parent.parent   # scripts/ -> project root
load_dotenv(BASE_DIR / ".env")                      # read .env into environment variables

DATA_DIR = BASE_DIR / os.getenv("DATA_DIR", "data/raw")
SOURCE_FILE = "olist_orders_dataset.csv"
ORDERS_FILE = DATA_DIR / SOURCE_FILE
ITEMS_FILE = DATA_DIR / "olist_order_items_dataset.csv"

# exchange-rate API (same key as Lab 1)
EXCHANGE_API_URL = os.getenv("EXCHANGE_API_URL", "https://v6.exchangerate-api.com/v6").strip().rstrip("/")
EXCHANGE_API_KEY = os.getenv("EXCHANGE_API_KEY")
RETRY_CODES = {429, 500, 502, 503, 504}   # temporary: retry with backoff
MAX_TRIES = 3

DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")
DB_HOST = os.getenv("DB_HOST")
DB_PORT = os.getenv("DB_PORT")
DB_NAME = os.getenv("DB_NAME")
DB_URL = (f"postgresql+psycopg2://{DB_USER}:{quote_plus(DB_PASSWORD or '')}"  # quote_plus: @ # in password stay safe
          f"@{DB_HOST}:{DB_PORT}/{DB_NAME}")

# one ID per run, saved on every row we load (lineage)
RUN_ID = datetime.now().strftime("%Y%m%d_%H%M%S")

DATE_FORMAT = "%d/%m/%Y %H:%M"   # original Olist CSV, e.g. 2017-10-02 10:56:33

DATE_COLUMNS = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date",
]
VALID_STATUSES = {"created", "approved", "invoiced", "processing",
                  "shipped", "delivered", "canceled", "unavailable"}

# source column names -> our staging names
RENAME_MAP = {
    "order_purchase_timestamp": "purchased_at",
    "order_approved_at": "approved_at",
    "order_delivered_carrier_date": "shipped_at",
    "order_delivered_customer_date": "delivered_at",
    "order_estimated_delivery_date": "estimated_delivery_at",
}

# ---------- SQL ----------
CREATE_TABLE_SQL = """
CREATE SCHEMA IF NOT EXISTS staging;

CREATE TABLE IF NOT EXISTS staging.stg_orders (
    order_id               TEXT PRIMARY KEY,
    customer_id            TEXT        NOT NULL,
    order_status           TEXT        NOT NULL,
    purchased_at           TIMESTAMP   NOT NULL,
    approved_at            TIMESTAMP,
    shipped_at             TIMESTAMP,
    delivered_at           TIMESTAMP,
    estimated_delivery_at  TIMESTAMP,
    delivery_days          INTEGER,
    is_late                BOOLEAN,
    order_total_brl        NUMERIC(12,2),
    brl_usd_rate           NUMERIC(12,6),
    order_total_usd        NUMERIC(12,2),
    _source_file           TEXT        NOT NULL,
    _run_id                TEXT        NOT NULL,
    _loaded_at             TIMESTAMP   NOT NULL DEFAULT now(),
    _updated_at            TIMESTAMP   NOT NULL DEFAULT now()
);

-- the table may already exist from Week 5: add the new columns if they are missing
ALTER TABLE staging.stg_orders ADD COLUMN IF NOT EXISTS order_total_brl NUMERIC(12,2);
ALTER TABLE staging.stg_orders ADD COLUMN IF NOT EXISTS brl_usd_rate    NUMERIC(12,6);
ALTER TABLE staging.stg_orders ADD COLUMN IF NOT EXISTS order_total_usd NUMERIC(12,2);
"""

UPSERT_SQL = """
INSERT INTO staging.stg_orders (
    order_id, customer_id, order_status, purchased_at, approved_at,
    shipped_at, delivered_at, estimated_delivery_at, delivery_days, is_late,
    order_total_brl, brl_usd_rate, order_total_usd,
    _source_file, _run_id
)
SELECT
    order_id, customer_id, order_status, purchased_at, approved_at,
    shipped_at, delivered_at, estimated_delivery_at,
    CAST(delivery_days AS INTEGER), CAST(is_late AS BOOLEAN),
    CAST(order_total_brl AS NUMERIC(12,2)), CAST(brl_usd_rate AS NUMERIC(12,6)),
    CAST(order_total_usd AS NUMERIC(12,2)),
    _source_file, _run_id
FROM staging._tmp_orders
ON CONFLICT (order_id) DO UPDATE SET
    customer_id           = EXCLUDED.customer_id,  -- EXCLUDED = the new row from the temp table
    order_status          = EXCLUDED.order_status,
    purchased_at          = EXCLUDED.purchased_at,
    approved_at           = EXCLUDED.approved_at,
    shipped_at            = EXCLUDED.shipped_at,
    delivered_at          = EXCLUDED.delivered_at,
    estimated_delivery_at = EXCLUDED.estimated_delivery_at,
    delivery_days         = EXCLUDED.delivery_days,
    is_late               = EXCLUDED.is_late,
    order_total_brl       = EXCLUDED.order_total_brl,
    brl_usd_rate          = EXCLUDED.brl_usd_rate,
    order_total_usd       = EXCLUDED.order_total_usd,
    _source_file          = EXCLUDED._source_file,
    _run_id               = EXCLUDED._run_id,
    _updated_at           = now()
-- only update rows where a business column really changed,
-- so _run_id and _updated_at show the last REAL change.
-- The rate changes every day, so it is NOT compared: otherwise every row
-- would be "updated" on every run. A row keeps the rate from its last real change.
WHERE (staging.stg_orders.customer_id, staging.stg_orders.order_status,
       staging.stg_orders.purchased_at, staging.stg_orders.approved_at,
       staging.stg_orders.shipped_at, staging.stg_orders.delivered_at,
       staging.stg_orders.estimated_delivery_at, staging.stg_orders.delivery_days,
       staging.stg_orders.is_late, staging.stg_orders.order_total_brl)
  IS DISTINCT FROM
      (EXCLUDED.customer_id, EXCLUDED.order_status,
       EXCLUDED.purchased_at, EXCLUDED.approved_at,
       EXCLUDED.shipped_at, EXCLUDED.delivered_at,
       EXCLUDED.estimated_delivery_at, EXCLUDED.delivery_days,
       EXCLUDED.is_late, EXCLUDED.order_total_brl)
   -- also fill USD for rows that have none yet (first run, or the API was down last time)
   OR (staging.stg_orders.order_total_usd IS NULL
       AND EXCLUDED.order_total_usd IS NOT NULL);
"""

# columns we compare to find what changed (lineage columns are not compared)
COMPARE_COLUMNS = [
    "customer_id", "order_status", "purchased_at", "approved_at", "shipped_at",
    "delivered_at", "estimated_delivery_at", "delivery_days", "is_late",
    "order_total_brl",
] # collect the columns (the rate and USD total are not compared - see UPSERT_SQL)
# pandas may give the temp table a different type, so cast before comparing
CASTS = {"delivery_days": "INTEGER", "is_late": "BOOLEAN", "order_total_brl": "NUMERIC(12,2)"} #key is column, value is type
MAX_CHANGES_IN_LOG = 20 # how many changes to log

# ---------- Logging ----------
(BASE_DIR / "logs").mkdir(exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.FileHandler(BASE_DIR / "logs" / "etl.log"),   # saved to a file
        logging.StreamHandler(),                              # and shown on screen
    ],
)
log = logging.getLogger(__name__) # logger for this module


# ---------- Extract ----------
def get_brl_to_usd():
    """Return today's USD value of 1 BRL, or None if the API is not available.

    Week 7 habits: retry what is temporary (429, 5xx, timeout) with backoff,
    give up at once on what is permanent (bad key, bad request).
    The rate is "nice to have": if it fails, we still load the orders, with USD left empty.
    """
    if not EXCHANGE_API_KEY:
        log.warning("EXCHANGE_API_KEY not set in .env - loading without USD")
        return None

    url = f"{EXCHANGE_API_URL}/{EXCHANGE_API_KEY}/pair/BRL/USD"
    for attempt in range(1, MAX_TRIES + 1):
        try:
            r = requests.get(url, timeout=10)
        except (requests.Timeout, requests.ConnectionError) as e:
            log.warning(f"Rate API {type(e).__name__} (attempt {attempt}) - retrying")
        else:
            if r.status_code in RETRY_CODES:
                log.warning(f"Rate API HTTP {r.status_code} (attempt {attempt}) - retrying")
            else:
                try:
                    data = r.json()
                except ValueError:
                    log.warning(f"Rate API HTTP {r.status_code}: response was not JSON - loading without USD")
                    return None
                if data.get("result") == "success":
                    rate = float(data["conversion_rate"])
                    log.info(f"Rate API: 1 BRL = {rate} USD")
                    return rate
                # permanent problem (invalid-key, unsupported-code ...): retrying will not help
                log.warning(f"Rate API error: {data.get('error-type')} - loading without USD")
                return None
        if attempt < MAX_TRIES:
            time.sleep(2 ** (attempt - 1))          # backoff: 1s, 2s

    log.warning(f"Rate API still failing after {MAX_TRIES} tries - loading without USD")
    return None


def extract():
    log.info(f"Extract: reading {ORDERS_FILE.name} and {ITEMS_FILE.name}") # method of the Logger object provided by Python's built-in logging module.
    try:
        # read every column as text: we decide the types ourselves in transform
        orders = pd.read_csv(ORDERS_FILE, dtype=str)
        items = pd.read_csv(ITEMS_FILE, dtype=str, usecols=["order_id", "price", "freight_value"])
    except FileNotFoundError as e:
        log.error(f"File not found: {e.filename}")
        raise

    log.info(f"Read {len(orders):,} orders and {len(items):,} order items")
    rate = get_brl_to_usd()
    return orders, items, rate


# ---------- Transform ----------
def drop_bad_rows(df, mask, reason):
    """Remove rows where mask is True and log how many."""
    count = int(mask.sum()) # True counts as 1
    if count:
        log.warning(f"Dropped {count} rows: {reason}") #
    return df[~mask].copy()                  # .copy(): no SettingWithCopyWarning later


def transform(orders, items, rate):
    log.info("Transform: cleaning, checking, renaming, adding columns")
    df = orders.copy()

    # 1. Clean text: remove spaces, lowercase the status
    for col in df.columns:
        df[col] = df[col].str.strip()
    df["order_status"] = df["order_status"].str.lower()

    # 2. Text to dates (bad values become NaT instead of crashing)
    for col in DATE_COLUMNS:
        df[col] = pd.to_datetime(df[col], format=DATE_FORMAT, errors="coerce")

    # 3. Quality checks: drop rows that break the table rules
    df = drop_bad_rows(df, df["order_id"].isna(), "missing order_id")
    df = drop_bad_rows(df, df["order_id"].duplicated(), "duplicate order_id")
    df = drop_bad_rows(df, df["customer_id"].isna(), "missing customer_id")
    df = drop_bad_rows(df, ~df["order_status"].isin(VALID_STATUSES), "unknown order_status")
    df = drop_bad_rows(df, df["order_purchase_timestamp"].isna(), "invalid purchase date")
    # approved_at may be empty (orders canceled before approval): that is normal, keep them

    # 4. New columns
    delivered = df["order_delivered_customer_date"]
    df["delivery_days"] = (delivered - df["order_purchase_timestamp"]).dt.days

    is_late = (delivered > df["order_estimated_delivery_date"]).astype("boolean")
    is_late[delivered.isna()] = pd.NA          # not delivered yet = unknown, not False
    df["is_late"] = is_late

    # order total in BRL = sum of (price + freight) over the order's items
    items = items.copy()
    for col in ["price", "freight_value"]:
        items[col] = pd.to_numeric(items[col].str.strip(), errors="coerce")
    totals = (items["price"] + items["freight_value"]).groupby(items["order_id"].str.strip()).sum()
    df["order_total_brl"] = df["order_id"].map(totals).round(2)   # no items -> empty (NaN)

    # today's rate and the total in USD (empty if the API was not available)
    df["brl_usd_rate"] = rate
    df["order_total_usd"] = (df["order_total_brl"] * rate).round(2) if rate is not None else None

    # 5. Rename to our naming convention
    df = df.rename(columns=RENAME_MAP)

    # 6. Lineage: where each row came from and which run loaded it
    df["_source_file"] = SOURCE_FILE
    df["_run_id"] = RUN_ID

    df = df[[
        "order_id", "customer_id", "order_status", "purchased_at", "approved_at",
        "shipped_at", "delivered_at", "estimated_delivery_at", "delivery_days",
        "is_late", "order_total_brl", "brl_usd_rate", "order_total_usd",
        "_source_file", "_run_id",
    ]] #dataframe with the columns in the order we want

    status_counts = df["order_status"].value_counts().to_dict() #dictionary #Series ကို dictionary ပြောင်းလဲ
    log.info(f"Orders by status: {status_counts}")
    log.info(f"Transform done: {len(df):,} rows")
    return df


# ---------- Load ----------
def find_changes(conn):
    """Compare the temp table with stg_orders. Return (new count, changes DataFrame)."""
    new_count = conn.execute(text("""
        SELECT COUNT(*) FROM staging._tmp_orders t
        WHERE NOT EXISTS (SELECT 1 FROM staging.stg_orders s WHERE s.order_id = t.order_id)
    """)).scalar()

    # one SELECT per column, glued together with UNION ALL
    parts = []
    for col in COMPARE_COLUMNS:
        if col in CASTS:

         new_val = f"CAST(t.{col} AS {CASTS[col]})"
        else:
         new_val = f"t.{col}"
        parts.append(f"""
            SELECT t.order_id, '{col}' AS column_name,
                   COALESCE(CAST(s.{col} AS TEXT), 'NULL') AS old_value,
                   COALESCE(CAST({new_val} AS TEXT), 'NULL') AS new_value
            FROM staging._tmp_orders t
            JOIN staging.stg_orders s ON s.order_id = t.order_id
            WHERE s.{col} IS DISTINCT FROM {new_val}""")
    sql = " UNION ALL ".join(parts) + " ORDER BY order_id, column_name"
    changes = pd.read_sql(text(sql), conn)
    return new_count, changes

def log_changes(total_rows, new_count, changes):
    """Write a summary, then one line per changed column (first MAX_CHANGES_IN_LOG)."""
    updated_count = changes["order_id"].nunique()
    unchanged = total_rows - new_count - updated_count
    log.info(f"New: {new_count:,} | Updated: {updated_count:,} | Unchanged: {unchanged:,}")

    for row in changes.head(MAX_CHANGES_IN_LOG).itertuples():
        log.info(f"Updated {row.order_id}: {row.column_name} "
                 f"'{row.old_value}' -> '{row.new_value}'")
    if len(changes) > MAX_CHANGES_IN_LOG:
        log.info(f"... and {len(changes) - MAX_CHANGES_IN_LOG:,} more column changes")


def load(df):
    log.info("Load: upsert into staging.stg_orders")
    try:
        engine = create_engine(DB_URL)

        # one transaction: everything is saved, or nothing is
        with engine.begin() as conn:
            conn.exec_driver_sql(CREATE_TABLE_SQL)                 # 1. table ready

            df.to_sql("_tmp_orders", conn, schema="staging",       # 2. rows into a temp table
                      if_exists="replace", index=False)

            new_count, changes = find_changes(conn)                # 3. what will change?

            conn.execute(text(UPSERT_SQL))                         # 4. insert new, update changed
            conn.execute(text("DROP TABLE staging._tmp_orders"))   # 5. clean up

            total = conn.execute(text("SELECT COUNT(*) FROM staging.stg_orders")).scalar()
    except Exception as e:
        log.error(f"Load failed: {e}")
        raise

    log_changes(len(df), new_count, changes)
    log.info(f"Upserted {len(df):,} rows (table now has {total:,} rows)")


# ---------- Run the pipeline ----------
def main():
    log.info(f"===== ETL started (run {RUN_ID}) =====")
    try:
        orders, items, rate = extract()
        result = transform(orders, items, rate)
        load(result)
    except Exception:
        log.exception("ETL failed")   # logs the full error details
        sys.exit(1)                   # non-zero exit = failure (Airflow uses this later)
    log.info("===== ETL finished successfully =====")


if __name__ == "__main__":
    main()