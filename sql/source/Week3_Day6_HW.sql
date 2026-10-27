--Q1. NULL audit: count NULLs in product_category_name and product_weight_g.

select count(*) - count(product_category_name) as product_category_name_nulls,
count(*) - count(product_weight_g ) as product_weight_g_nulls
from products;


--Q2.For each month of purchase, what is the average delivery time, 
--and how many orders (and what percentage) were delivered within 30 days of purchase?

select
    date_trunc('month', order_purchase_timestamp)::date AS purchase_month,

    round(
        avg(
            extract(
                epoch from (
                    order_delivered_customer_date
                    - order_purchase_timestamp
                )
            ) / 86400
        )::numeric,
        2
    ) as avg_delivery_days,

    count(*) filter (
        where order_delivered_customer_date is not null
          and order_delivered_customer_date >= order_purchase_timestamp
          and order_delivered_customer_date
              <= order_purchase_timestamp + interval '30 days'
    ) as orders_within_30_days,

    round(
        100.0 * count(*) filter (
            where order_delivered_customer_date is not null
              and order_delivered_customer_date >= order_purchase_timestamp
              and order_delivered_customer_date
                  <= order_purchase_timestamp + interval  '30 days'
        ) / nullif(count(*), 0),
        2
    ) as percentage_within_30_days

from orders
group by date_trunc('month', order_purchase_timestamp)::date
order by purchase_month;





--Q.3 On which day of the week do customers place the most orders? Show each weekday’s name and number,
 --and the total orders for that day, sorted from busiest to quietest. ----


select
    trim(to_char(order_purchase_timestamp, 'Day')) as weekday_name,
    extract(isodow from order_purchase_timestamp)::int as weekday_number,
    COUNT(order_id) as total_orders
from orders
group by
    extract(isodow from order_purchase_timestamp),
    trim(to_char(order_purchase_timestamp, 'Day'))
order by total_orders desc;

 
 
 
 --Q4.What is the total revenue for each product category, shown with its English name?
 -- If a category has no English translation, show the original Portuguese name instead.
 -- If the product has no category at all, show it as ‘unknown’.
select * from category_translation ct ;

select  coalesce(ct.product_category_name_english ,p.product_category_name ,'unknown') as product_category_name,SUM(oi.freight_value + oi.price ) as total_revenue
from orders o 
join order_items oi  using(order_id)
join products p using(product_id)
left join category_translation ct  using(product_category_name)
group by coalesce(ct.product_category_name_english ,p.product_category_name ,'unknown')
order by total_revenue desc;

--Q.5 Group delivered orders by delivery speed: • Fast: 7 days or less from purchase to delivery. • Normal: 8 to 14 days. • Slow: 15 to 30 days. • Very slow: more than 30 days. How many orders fall into each group, and what percentage of the total is each?



with delivery_times as (
select order_id,
order_delivered_customer_date  - order_purchase_timestamp  as delivery_duration
from orders 
where order_delivered_customer_date is not null 
and order_delivered_customer_date >= order_purchase_timestamp 
),
delivery_groups as (
select case 
	when delivery_duration <= interval '7 days' then 'Fast'
	when delivery_duration <= interval '14 days' then 'Normal'
	when delivery_duration <= interval '30 days' then 'Slow'
	else 'Very Slow'
end as delivery_speed
from delivery_times 
)
select 
    delivery_speed,
    count(*) as total_orders,
    round(
        100.0 * count(*) / sum(count(*)) over (),
        2
    ) as percentage
from delivery_groups
group by delivery_speed
order by
    case delivery_speed
        when 'Fast' then 1
        when 'Normal' then 2
        when 'Slow' then 3
        when 'Very slow' then 4
    end;

