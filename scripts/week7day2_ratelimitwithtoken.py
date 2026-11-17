"""Read GitHub rate-limit headers after every response (token optional)."""

import os
import time
from pathlib import Path

import requests
import truststore
from dotenv import load_dotenv

truststore.inject_into_ssl()

BASE_DIR = Path(__file__).resolve().parent.parent   # scripts/ -> project root
load_dotenv(BASE_DIR / ".env")

token = os.getenv("GITHUB_TOKEN")
headers = {"Authorization": f"Bearer {token}"} if token else {}
print("Using token:", bool(token))


def check_rate_limit(r: requests.Response, min_left: int = 5) -> None:
    """Print the rate-limit headers and sleep until reset if we're nearly out."""
    remaining = int(r.headers.get("X-RateLimit-Remaining", 1))
    limit = int(r.headers.get("X-RateLimit-Limit", 0))
    reset_at = int(r.headers.get("X-RateLimit-Reset", time.time()))
    wait = max(reset_at - time.time(), 0)
    print(f"rate limit: {remaining}/{limit} left, resets in {wait / 60:.0f} min")

    if remaining < min_left:
        print(f"Almost out of calls - sleeping {wait + 1:.0f}s until reset")
        time.sleep(wait + 1)


def get_all_pages(url, params=None, headers=None, max_pages=2):
    """Fetch up to max_pages pages, checking the rate limit after every response."""
    rows = []
    for _ in range(max_pages):
        r = requests.get(url, params=params, headers=headers, timeout=10)
        r.raise_for_status()
        check_rate_limit(r)          # read the headers after every response
        rows.extend(r.json())
        url = r.links.get("next", {}).get("url")
        params = None
        if url is None:
            break
    return rows


rows = get_all_pages("https://api.github.com/orgs/microsoft/repos", {"per_page": 100}, headers=headers)
print("repos fetched:", len(rows))