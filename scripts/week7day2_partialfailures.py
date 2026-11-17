"""Olist extract step: CSV -> Parquet, surviving partial failures (5 habits)."""

import json
import os
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv

# ---------- settings from .env ----------
BASE_DIR = Path(__file__).resolve().parent.parent   # scripts/ -> project root
load_dotenv(BASE_DIR / ".env")

data_dir = os.getenv("DATA_DIR")
output_dir = os.getenv("OUTPUT_DIR")
if not data_dir or not output_dir:
    raise RuntimeError("DATA_DIR and OUTPUT_DIR must be set in the .env file in the project root.")

DATA_DIR = BASE_DIR / data_dir
OUT_DIR = BASE_DIR / output_dir / "staging_parquet"
OUT_DIR.mkdir(parents=True, exist_ok=True)

FAILED_FILE = OUT_DIR / "failed.json"
MAX_FAILURES = 3                                    # 5 our own limit

TABLES = {
    "orders":      "olist_orders_datasetd.csv",
    "customers":   "olist_customers_datasetd.csv",
    "order_items": "olist_order_items_datasetd.csv",
    "payments":    "olist_order_payments_datasetd.csv",   # broken on purpose for Run 1
    "reviews":     "olist_order_reviews_dataset.csv",
    "products":    "olist_products_dataset.csv",
    "sellers":     "olist_sellers_dataset.csv",
    "geolocation": "olist_geolocation_dataset.csv",
    "categories":  "product_category_name_translation.csv",
}

# 4 rerun only what failed last time
if FAILED_FILE.exists():
    previous = json.loads(FAILED_FILE.read_text())
    TABLES = {t: f for t, f in TABLES.items() if t in previous}
    print("Rerunning only previous failures:", list(TABLES))

# ---------- the loop ----------
ok, failed = {}, {}

for table, csv_name in TABLES.items():
    try:
        df = pd.read_csv(DATA_DIR / csv_name)
        df.to_parquet(OUT_DIR / f"{table}.parquet", index=False)   # 1 save now
        ok[table] = len(df)
        print(f"OK    {table:<12} {len(df):>7} rows")
    except Exception as e:
        failed[table] = f"{type(e).__name__}: {e}"                  # 2 record why
        print(f"FAIL  {table:<12} {type(e).__name__}")
        if len(failed) >= MAX_FAILURES:                             # 5 stop
            print(f"\nSTOP: {len(failed)} tables failed - probably one shared cause. "
                  "Check DATA_DIR in .env and that the CSVs are in place.")
            break

# ---------- 3 report ----------
print("\n========== RUN REPORT ==========")
print(f"loaded: {len(ok)}  failed: {len(failed)}")
for table, reason in failed.items():
    print(f"  - {table}: {reason[:70]}")

# ---------- 4 rerun list ----------
if failed:
    FAILED_FILE.write_text(json.dumps(failed, indent=2))
    print(f"\nSaved failures to {FAILED_FILE.name} - fix them, then run again.")
elif FAILED_FILE.exists():
    FAILED_FILE.unlink()
    print("\nAll failures fixed - failed.json removed.")