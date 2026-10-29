
-- Some orders have more than one review.
-- Keep only the most recent review per order.

with ranked as(
select r.*,
row_number() over(
partition by order_id 
order by  review_answer_timestamp DESC,
                    review_id

) as rn 
from order_reviews r

)
select * from  ranked where rn = 1;

WITH monthly AS (
SELECT DATE_TRUNC('month', order_purchase_timestamp) AS month,
COUNT(*) AS orders
FROM raw.orders
WHERE order_purchase_timestamp >= '2017-01-01'
AND order_purchase_timestamp < '2018-01-01'
GROUP BY 1
)
SELECT TO_CHAR(month, 'YYYY-MM') AS month,
orders,
LAG(orders) OVER (ORDER BY month) AS prev_month_orders,
LEAD(orders) OVER (ORDER BY month) AS next_month_orders
FROM monthly
ORDER BY month;


WITH monthly AS (
  SELECT DATE_TRUNC('month', o.order_purchase_timestamp)
           AS month,
         SUM(oi.price) AS revenue
  FROM raw.orders o
  JOIN raw.order_items oi USING (order_id)
  WHERE o.order_status = 'delivered'
  GROUP BY 1
)
SELECT month, revenue,
       LAG(revenue) OVER (ORDER BY month) AS prev,
       ROUND(100.0 * (revenue - LAG(revenue)
             OVER (ORDER BY month))
         / NULLIF(LAG(revenue) OVER (ORDER BY month), 0)
       , 1) AS mom_growth_pct
FROM monthly ORDER BY month;
--Cumulative revenue and a 3-month moving  --
WITH monthly AS (
  SELECT DATE_TRUNC('month', o.order_purchase_timestamp)
           AS month,
         SUM(oi.price) AS revenue
  FROM raw.orders o
  JOIN raw.order_items oi USING (order_id)
  WHERE o.order_status = 'delivered'
  GROUP BY 1
)

SELECT month, revenue,
       SUM(revenue) OVER (
         ORDER BY month
        ROWS BETWEEN 2 PRECEDING
                  AND CURRENT ROW) AS running_total,
       ROUND(AVG(revenue) OVER (
         ORDER BY month
         ROWS BETWEEN 2 PRECEDING
                  AND CURRENT ROW), 2) AS ma_3m,
       ROUND(100.0 * revenue
         / SUM(revenue) OVER (), 2) AS pct_of_total
FROM monthly ORDER BY month;

select 134.97+40325.11+10.90

WITH monthly AS (
  SELECT DATE_TRUNC('month', o.order_purchase_timestamp)
           AS month,
         SUM(oi.price) AS revenue
  FROM raw.orders o
  JOIN raw.order_items oi USING (order_id)
  WHERE o.order_status = 'delivered'
  GROUP BY 1
)
SELECT month, revenue,
       SUM(revenue) OVER (
         ORDER BY month
         ROWS BETWEEN UNBOUNDED PRECEDING
                  AND CURRENT ROW) AS running_total,
       ROUND(AVG(revenue) OVER (
         ORDER BY month
         ROWS BETWEEN 2 PRECEDING
                  AND CURRENT ROW), 2) AS ma_3m,
       ROUND(100.0 * revenue
         / SUM(revenue) OVER (), 2) AS pct_of_total
FROM monthly ORDER BY month;

--Q1.For each seller state, find the 3 sellers who earned the most revenue.---
with seller_revenue as (
select oi.seller_id,seller_state,SUM(oi.price + oi.freight_value) as revenue  from order_items oi  join sellers s  on oi.seller_id = s.seller_id 
group by oi.seller_id,s.seller_state 
),
ranked as (
select s.* ,rank() over(partition by seller_state order by revenue desc  ) as rnk 
from seller_revenue s
)
select * from ranked 

where rnk <= 3

order by revenue desc;


-- Top 3 sellers by revenue within each state
-- Ties share the same rank

with seller_revenue as (
    select
        s.seller_id,
        s.seller_state,
        SUM(oi.price) as total_revenue
    from raw.sellers s
    join raw.order_items oi
        on s.seller_id = oi.seller_id
    group by
        s.seller_id,
        s.seller_state
),
ranked_sellers as (
    select
        seller_id,
        seller_state,
        total_revenue,
        rank() over (
            partition by  seller_state
            order by total_revenue desc
        ) as rnk
    from seller_revenue
)
select
    seller_state,
    seller_id,
    total_revenue,
    rnk
from ranked_sellers
where rnk <= 3
order by
    seller_state,
    rnk,
    seller_id;

--Q2.For every customer, show the date of their first order and how many orders they placed in total.--


with customer_orders as (
    select
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        row_number() OVER (
            partition by  c.customer_unique_id
             order by  o.order_purchase_timestamp, o.order_id
        ) AS rn,
        count(*) over (
             partition by c.customer_unique_id
        ) as total_orders
    from orders o
    join customers c
        on o.customer_id = c.customer_id
)
select
    customer_unique_id,
    order_purchase_timestamp::date as first_order_date,
    total_orders
from customer_orders
where rn = 1
order by customer_unique_id;

--Q3.For each seller, show how their revenue adds up over time, order by order.

-- running revenue for each seller, order by order

with order_revenue as (
    select
        oi.seller_id,
        oi.order_id,
        o.order_purchase_timestamp,
        sum(oi.price + oi.freight_value) as order_revenue
    from raw.order_items oi
    join raw.orders o
        on oi.order_id = o.order_id
    group by
        oi.seller_id,
        oi.order_id,
        o.order_purchase_timestamp
)
select
    seller_id,
    order_id,
    order_purchase_timestamp,
    order_revenue,
    sum(order_revenue) over (
        partition by seller_id
        order by order_purchase_timestamp, order_id
        rows between unbounded preceding and current row
    ) as running_revenue
from order_revenue
order by
    seller_id,
    order_purchase_timestamp,
    order_id;

--Q4.---What percentage of all money paid came from each payment type? ---

select
    payment_type,
    sum(payment_value) as total_paid,
    round(
        100.0 * sum(payment_value) / sum(sum(payment_value)) over (),
        1
    ) as pct_of_total
from raw.order_payments
group by payment_type
order by total_paid desc;

--Q5.Find the order items whose price is higher than the average price in their product category.---

with item_category_avg as (
    select
        oi.order_id,
        oi.product_id,
        p.product_category_name as category,
        oi.price,
        avg(oi.price) over (
            partition by p.product_category_name
        ) as category_avg
    from raw.order_items oi
    join raw.products p
        on oi.product_id = p.product_id
    where p.product_category_name is not null
)
select
    order_id,
    product_id,
    category,
    price,
    round(category_avg::numeric, 2) as category_avg
from item_category_avg
where price > category_avg
order by category, price desc;




