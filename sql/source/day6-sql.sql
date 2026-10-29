select order_purchase_timestamp,order_purchase_timestamp:: date,cast(order_purchase_timestamp as DATE)

from orders limit 5;

select customer_zip_code_prefix ,customer_zip_code_prefix :: int
from customers
where customer_zip_code_prefix  like '0%' limit 3;

SELECT ROUND(123.456, 2)   AS r2,      -- 123.46
       ROUND(123.456, -1)  AS r_tens,  -- 120-- -1 means “round to the nearest ten”
       TRUNC(123.456, 1)   AS t1,      -- 123.4
       CEIL(4.1)           AS up,      -- 5
       FLOOR(4.9)          AS down;    

select round(geolocation_lat::numeric ,3)
from geolocation;

-- Bucketing, clamping, distance, parity
SELECT FLOOR(price / 50) * 50    AS price_band,
       GREATEST(freight_value, 0) AS freight,
       LEAST(price, 1000)        AS capped_price,--“give me the smaller of price and 1000
       ABS(price - 100)          AS dist_from_100,-- “how far is the price from 100
       MOD(order_item_id, 2)     AS odd_even --order_item_id/2 (reminder)
FROM raw.order_items LIMIT 5;
SELECT
  COUNT(*) - COUNT(order_approved_at)
      AS approved_at_nulls,
  COUNT(*) - COUNT(order_delivered_carrier_date)
      AS carrier_nulls,
  COUNT(*) - COUNT(order_delivered_customer_date)
      AS delivered_nulls
FROM raw.orders;

select coalesce(review_comment_title ,'(no title)') from order_reviews ;

select sum(price)/nullif(count(*),0)
from order_items oi ;

select  o.order_id ,coalesce(sum(op.payment_value),0) as paid from orders o join order_payments op
using (order_id) group by o.order_id ;

select coalesce(product_weight_g::text,'unknown')
from products;

SELECT COALESCE(order_delivered_customer_date,
                order_delivered_carrier_date,
                order_purchase_timestamp) AS last_event
FROM orders LIMIT 5;

select order_delivered_customer_date,order_delivered_carrier_date,order_purchase_timestamp
from orders limit 5;

select coalesce(nullif(trim(product_category_name,' '),'unknown'))
from products;


select case 
	when price is null then 'missing'
	when price < 50  then 'low'
	when price < 200 then 'mid'
	else 'high'
end

from order_items;

select case
when payment_value is null  then 'missing'
when payment_value < 50 then 'low'
when payment_value < 200 then 'mid'
else 'high'
end
from order_payments;

select  oi.order_id, c.customer_state, oi.freight_value
from order_items oi  join orders o using(order_id)
join customers c using(customer_id)
where oi.freight_value >
case when c.customer_state  in ('SP', 'RJ')  then 20 
else 40 end;

select  oi.order_id, c.customer_state, oi.freight_value,o.order_status 
from order_items oi  join orders o using(order_id)
join customers c using(customer_id)
WHERE CASE WHEN order_status = 'delivered' THEN TRUE END


SELECT order_purchase_timestamp            AS ts,
       order_purchase_timestamp::date      AS day,
       DATE_TRUNC('month', order_purchase_timestamp)
                                           AS month,
       EXTRACT(YEAR FROM order_purchase_timestamp)
                                           AS yr,
       EXTRACT(DOW FROM order_purchase_timestamp)
                                           AS weekday, -- 0=Sun
       TO_CHAR(order_purchase_timestamp, 'YYYY-MM')
                                           AS ym_text,
       order_purchase_timestamp
         + INTERVAL '30 days'              AS plus_30d
FROM raw.orders LIMIT 5;

select current_date ,now();
SELECT TO_DATE('15/03/2018', 'DD/MM/YYYY'),
       TO_TIMESTAMP('2018-03-15 14:05',
                    'YYYY-MM-DD HH24:MI'),
       MAKE_DATE(2018, 3, 15);


SELECT AGE(order_delivered_customer_date,--how much time passed from
           order_purchase_timestamp)      AS age,
       EXTRACT(EPOCH FROM
         order_delivered_customer_date
         - order_purchase_timestamp) / 3600 AS hours
FROM raw.orders LIMIT 5;

select order_delivered_customer_date,order_purchase_timestamp from orders;

SELECT order_purchase_timestamp
         AT TIME ZONE 'America/Sao_Paulo' AS tz_aware,
       (order_purchase_timestamp
         AT TIME ZONE 'America/Sao_Paulo')
         AT TIME ZONE 'Asia/Bangkok'      AS bangkok_time
FROM raw.orders LIMIT 5;

SELECT d::date            AS day,
       COUNT(o.order_id)  AS orders
FROM GENERATE_SERIES('2018-01-01'::timestamp,
                     '2018-01-31'::timestamp,
                     INTERVAL '1 day') AS d
LEFT JOIN raw.orders o
  ON  o.order_purchase_timestamp >= d
  AND o.order_purchase_timestamp <  d + INTERVAL '1 day'
GROUP BY d ORDER BY d;

WITH classified_orders AS (
    SELECT
        CASE
            WHEN order_delivered_customer_date IS NULL
                THEN 'not delivered'
            WHEN order_delivered_customer_date - order_purchase_timestamp
                 <= INTERVAL '7 days'
                THEN 'fast'
            WHEN order_delivered_customer_date - order_purchase_timestamp
                 <= INTERVAL '14 days'
                THEN 'normal'
            ELSE 'slow'
        END AS delivery_bucket
    FROM raw.orders
),
bucket_counts AS (
    SELECT
        delivery_bucket,
        COUNT(*) AS orders
    FROM classified_orders
    GROUP BY delivery_bucket
)
SELECT
    delivery_bucket,
    orders,
    ROUND(
        100.0 * orders / (SELECT COUNT(*) FROM raw.orders),
        1
    ) AS pct_of_orders
FROM bucket_counts
ORDER BY orders DESC;








