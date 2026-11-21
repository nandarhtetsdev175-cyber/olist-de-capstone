"""Load settings from the .env file in the project root."""

import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent   # scripts/ -> project root
load_dotenv(BASE_DIR / ".env")                      # read .env into environment variables

# Paths (relative to the project root)
data_dir = os.getenv("DATA_DIR")
output_dir = os.getenv("OUTPUT_DIR")
if not data_dir or not output_dir:
    raise RuntimeError("DATA_DIR and OUTPUT_DIR must be set in the .env file in the project root.")

DATA_DIR = BASE_DIR / data_dir
OUTPUT_DIR = BASE_DIR / output_dir

# APIs
EXCHANGE_API_URL = os.getenv("EXCHANGE_API_URL", "https://v6.exchangerate-api.com/v6")
EXCHANGE_API_KEY = os.getenv("EXCHANGE_API_KEY")
GITHUB_API_URL = os.getenv("GITHUB_API_URL", "https://api.github.com")
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")  # optional: works without it, but with a lower rate limit