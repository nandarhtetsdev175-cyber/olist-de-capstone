import time
import requests

r = requests.get("https://api.github.com/orgs/microsoft/repos", timeout=10)#body
#GitHub’s API server,
#The rate-limit headers are about your usage, not about Microsoft’s repos. If you call a completely different endpoint, the count continues:
#body is the answer to your question; the headers are GitHub telling you how many more questions you’re allowed to ask.
limit     = int(r.headers["X-RateLimit-Limit"])      # max calls per hour
remaining = int(r.headers["X-RateLimit-Remaining"])  # calls left
reset_at  = int(r.headers["X-RateLimit-Reset"])      # when it refills (Unix time)

wait = max(reset_at - time.time(), 0)
print(f"{remaining}/{limit} calls left, resets in {wait/60:.0f} min")