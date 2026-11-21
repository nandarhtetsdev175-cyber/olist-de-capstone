"""Detect when the GitHub rate limit is used up (reactive check)."""

import time
from datetime import datetime
from zoneinfo import ZoneInfo

import requests
import truststore

truststore.inject_into_ssl()

url = "https://api.github.com/orgs/microsoft/repos"
params = {"per_page": 100}

r = requests.get(url, params=params, timeout=10)

limit = r.headers.get("x-ratelimit-limit")
remaining = r.headers.get("x-ratelimit-remaining")
reset = int(r.headers.get("x-ratelimit-reset", 0))   # epoch seconds
reset_bkk = datetime.fromtimestamp(reset, tz=ZoneInfo("Asia/Bangkok")).strftime("%I:%M:%S %p")

print(f"{remaining} of {limit} requests left")

if r.status_code in (403, 429) and remaining == "0":
    wait = max(reset - time.time(), 0)
    print(f"Limit used up. It resets in {wait / 60:.0f} minutes (at {reset_bkk} BKK).")
else:
    r.raise_for_status()                 # stop on any other error
    repos = r.json()                     # the body: list of repos
    print(f"OK - fetched {len(repos)} repos. Window resets at {reset_bkk} BKK.")