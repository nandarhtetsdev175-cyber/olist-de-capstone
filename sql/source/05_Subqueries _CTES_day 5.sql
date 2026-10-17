--Q5.For 5 orders, show item revenue and payment total side by side — without fan-out.---

with revenue as (
select order_id,sum(price + freight_value )as items_revenue  from order_items 
group by order_id
),
payment as 
(
select order_id, sum(payment_value ) as order_payments from order_payments
group by order_id 
)
select r.order_id,items_revenue,order_payments from revenue  r left join payment  p
on r.order_id  =  p.order_id 

--Q3.Sellers with no 1-star reviews at all — use NOT EXISTS.---

select s.seller_id FROM sellers s 
where  not exists (
select 1 from order_items oi join order_reviews t 
on oi.order_id  = t.order_id 
where oi.seller_id  = s.seller_id 
and t.review_score  = 1
) 

---Q4 ---Monthly revenue for delivered order---
WITH delivered_orders AS (
    SELECT order_id, order_purchase_timestamp
    FROM orders
    WHERE order_status = 'delivered'
),
order_revenue AS (
    SELECT order_id, SUM(price + freight_value) AS revenue
    FROM order_items
    GROUP BY order_id
)
SELECT DATE_TRUNC('month', d.order_purchase_timestamp) AS month,
       SUM(r.revenue) AS monthly_revenue
FROM delivered_orders d
JOIN order_revenue r ON r.order_id = d.order_id
GROUP BY 1
ORDER BY 1;

--Q5 --for each month .Which product category earned the most delivered status--
WITH delivered_orders AS (
    SELECT order_id, order_purchase_timestamp
    FROM orders
    WHERE order_status = 'delivered'
),
category_monthly AS (
    SELECT DATE_TRUNC('month', d.order_purchase_timestamp) AS month,
           p.product_category_name,
           SUM(oi.price) AS revenue
    FROM delivered_orders d
    JOIN order_items oi ON oi.order_id = d.order_id
    JOIN products p ON p.product_id = oi.product_id
    GROUP BY 1, 2
)
SELECT month, product_category_name, revenue
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY month ORDER BY revenue DESC) AS rn
    FROM category_monthly
) ranked
WHERE rn = 1
ORDER BY month limit 10;