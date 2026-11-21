"""Lab 1: fetch the BRL to USD rate, add price_usd to Olist order items, save as Parquet."""

import os
from pathlib import Path

import pandas as pd
import requests
import truststore
from dotenv import load_dotenv

truststore.inject_into_ssl()

BASE_DIR = Path(__file__).resolve().parent.parent   # scripts/ -> project root
load_dotenv(BASE_DIR / ".env")                      # read .env into environment variables

data_dir = os.getenv("DATA_DIR")
output_dir = os.getenv("OUTPUT_DIR")
EXCHANGE_API_URL = os.getenv("EXCHANGE_API_URL", "https://v6.exchangerate-api.com/v6")
EXCHANGE_API_KEY = os.getenv("EXCHANGE_API_KEY")
if not data_dir or not output_dir or not EXCHANGE_API_KEY:
    raise RuntimeError("DATA_DIR, OUTPUT_DIR and EXCHANGE_API_KEY must be set in the .env file in the project root.")

ITEMS_CSV = BASE_DIR / data_dir / "olist_order_items_dataset.csv"
OUT_PATH = BASE_DIR / output_dir / "order_items_usd.parquet"


def get_brl_to_usd() -> float:
    """Return the current USD value of 1 BRL, raising RuntimeError with the HTTP code on failure."""
    base = EXCHANGE_API_URL.strip().rstrip("/")
    url = f"{base}/{EXCHANGE_API_KEY}/latest/BRL"
    r = requests.get(url, timeout=10)
    try:
        data = r.json()
    except ValueError:
        raise RuntimeError(f"HTTP {r.status_code} {r.reason} (response was not JSON)") from None
    if data["result"] != "success":
        raise RuntimeError(f"HTTP {r.status_code}: {data['error-type']}")
    return data["conversion_rates"]["USD"]


def main() -> None:
    """Fetch the rate, add price_usd to order items, write Parquet and verify the column."""
    try:
        rate = get_brl_to_usd()
    except RuntimeError as exc:
        print("API error:", exc)
        raise SystemExit(1)
    except requests.RequestException as exc:
        print("Request failed:", type(exc).__name__)
        raise SystemExit(1)

    print("1 BRL =", rate, "USD")

    if not ITEMS_CSV.exists():
        print("CSV not found:", ITEMS_CSV)
        raise SystemExit(1)

    items = pd.read_csv(ITEMS_CSV)
    items["price_usd"] = (items["price"] * rate).round(2)

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)  # make sure data/ exists
    items.to_parquet(OUT_PATH, index=False)

    check = pd.read_parquet(OUT_PATH)
    print("price_usd column present:", "price_usd" in check.columns, check.shape)
    print(check[["price", "price_usd"]].head(3))


if __name__ == "__main__":
    main()