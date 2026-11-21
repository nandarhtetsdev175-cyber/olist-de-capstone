import os
from dotenv import load_dotenv

load_dotenv()        # read .env into environment variables

DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("postgres")   