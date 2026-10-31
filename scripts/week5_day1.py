from datetime import datetime

print("A")          # 1. runs        -> A

def extract():
    print("B")      # 2. skipped: only defined

print("C")          # 3. runs        -> C

extract()   
# 4. called now  -> B
a = [1, 2]
b = a            # same object, two names
b.append(3)
print(a)         # [1, 2, 3]

c = a.copy()     # a new object
c.append(4)
print(a)         



def calc_delivery_days(purchase, delivered):
    """Return days between purchase and delivery."""
    days = (delivered - purchase).days
    return days

start = datetime(2018, 1, 1)
end = datetime(2018, 1, 8)
result = calc_delivery_days(start, end)
print(result)   # 7
