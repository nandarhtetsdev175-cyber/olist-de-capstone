import time
from datetime import datetime

import requests
import truststore

truststore.inject_into_ssl()

def now():
    return datetime.now().strftime("%H:%M:%S")
#url = "https://httpbin.org/status/503"   # always "server problem"

url = "https://httpbin.org/status/503,503,200"   # 2/3 chance of 503, 1/3 chance of 200

for attempt in range(1, 5):
    r = requests.get(url, timeout=10)
    print(f"{now()}  attempt {attempt}: {r.status_code}")
    if r.status_code == 200:
        break
    wait = 2 ** (attempt - 1)            # 1, 2, 4, 8 seconds ← backoff: calculate a longer wait each time
    print(f"          waiting {wait}s ...")
    time.sleep(wait) #← backoff: actually wait before retrying