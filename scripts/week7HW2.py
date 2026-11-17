"""Q2: Join olist_orders_dataset.csv with olist_customers_dataset.csv on
    customer_id (IDs as strings, timestamps parsed). Write the result to
    Parquet partitioned by customer_state, read back only SP using
    filters=, and report the folder count + filtered row count."""

# =====================================================================
# orders + customers -> partitioned by customer_state -> read SP
# =====================================================================
import os
import shutil
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent   # project root
load_dotenv(BASE_DIR / ".env")
DATA_DIR = BASE_DIR / os.getenv("DATA_DIR", "data/raw")
OUT_DIR = BASE_DIR / os.getenv("OUTPUT_DIR", "data/processed")
OUT_DIR.mkdir(parents=True, exist_ok=True)

print("=" * 60)
print("orders+customers -> partitioned by customer_state")
print("=" * 60)

orders = pd.read_csv(
    DATA_DIR / "olist_orders_dataset.csv",
    encoding="utf-8",
    dtype={"order_id": "string",
           "customer_id": "string"},
    parse_dates=["order_purchase_timestamp",
                 "order_approved_at",
                 "order_delivered_carrier_date",
                 "order_delivered_customer_date",
                 "order_estimated_delivery_date"],
)

customers = pd.read_csv(
    DATA_DIR / "olist_customers_dataset.csv",
    encoding="utf-8",
    dtype={"customer_id": "string",
           "customer_unique_id": "string",
           "customer_zip_code_prefix": "string"},
)

# join on customer_id 
df = orders.merge(
    customers[["customer_id", "customer_state", "customer_city"]],
    on="customer_id",
    how="left",
)
print(f"joined rows: {len(df)}")
print("orders without a customer match:",
      df["customer_state"].isna().sum())

# write partitioned parquet by customer state
part_dir = OUT_DIR / "orders_by_state"
shutil.rmtree(part_dir, ignore_errors=True)
df.to_parquet(part_dir, partition_cols=["customer_state"], index=False)

# folder count = one folder per distinct state
state_dirs = [p for p in part_dir.iterdir() if p.is_dir()]
print(f"partition folders: {len(state_dirs)}")
print(sorted(p.name for p in state_dirs))

# read back only SP using filters 
sp = pd.read_parquet(part_dir, filters=[("customer_state", "==", "SP")])
print(f"SP rows: {len(sp)}")

# sanity check against the in-memory frame
print("expected SP rows from df:", (df["customer_state"] == "SP").sum())
