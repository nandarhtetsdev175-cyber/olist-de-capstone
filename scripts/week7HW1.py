"""
Q1: Load olist_order_reviews_dataset.csv safely (encoding, string IDs,
    parsed dates). Save it as Parquet, then read the parquet file back.,"""


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


# =====================================================================
#  reviews CSV -> Parquet -> read back
# =====================================================================
print("=" * 60)
print("Q1: reviews -> parquet")
print("=" * 60)

reviews = pd.read_csv(
    DATA_DIR / "olist_order_reviews_dataset.csv",
    encoding="utf-8",
    dtype={"review_id": "string",
           "order_id": "string"},
    parse_dates=["review_creation_date",
                 "review_answer_timestamp"],
)

print(reviews.dtypes)
print(f"reviews: {len(reviews)} rows")


reviews_path = OUT_DIR / "olist_order_reviews.parquet"
reviews.to_parquet(reviews_path, index=False)
# write + read back
reviews_back = pd.read_parquet(reviews_path)
print(f"parquet read back: {len(reviews_back)} rows")
print(reviews_back.dtypes)