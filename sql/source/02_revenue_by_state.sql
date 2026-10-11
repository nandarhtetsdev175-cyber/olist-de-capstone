select * from orders limit 5;

select c.customer_id ,c.customer_state ,o.order_id ,o.order_status  from customers c join orders  o
on c.customer_id  =  o.customer_id

select count(*) from orders o join order_reviews r
on o.order_id  =  r.order_id


select * from orders

select * from order_items

select count(1) from order_reviews t 

select count(*) from orders o left join order_reviews r
on o.order_id  =  r.order_id where r.order_id  is null

select 99992 -99441

--Q1.Revenue (SUM of price) by customer_state for delivered orders. Top 10 states.--
 select c.customer_state ,SUM(oi.price) as price  from orders o join customers c 
 on o.customer_id = c.customer_id
join order_items oi on o.order_id = oi.order_id 
where o.order_status = 'delivered'
group by c.customer_state
order by price desc limit 10

---Q.2 How many orders have no review at all? (anti-join)20:55--

select count(*) review_count from orders o left join order_reviews t  on o.order_id = t.order_id
where t.order_id is null

--Q3 Q;3: Top 10 product categories in English by items sold. Why LEFT JOIN to the translation?
select * from products limit 10;
select * from orders limit 10;
select * from order_items limit 10;
select * from category_translation ct  limit 10;


select ct.product_category_name_english,count(*) as item_sold   from order_items ot join products p 
on ot.product_id  = p.product_id
left join category_translation ct  on 
ct.product_category_name  = p.product_category_name 
group by product_category_name_english
order by item_sold desc limit 10

---Q4 .What share of order items were sold by a seller in the same state as the customer?--
select * from sellers limit 10;

select * from orders limit 10;
select * from customers limit 10;


---Q5.For 5 orders, show item revenue and payment total side by side — without fan-out.---

select * from order_payments limit 10;
SELECT
    i.order_id,
    i.item_revenue,
    p.payment_total
FROM (
    SELECT
        order_id,
        SUM(price) AS item_revenue
    FROM order_items
    GROUP BY order_id
) i
JOIN (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total
    FROM order_payments
    GROUP BY order_id
) p
    ON i.order_id = p.order_id
LIMIT 5;
SELECT
    oi.order_id,
    SUM(DISTINCT oi.price) AS item_revenue,
    SUM(DISTINCT op.payment_value) AS payment_total
FROM order_items oi
JOIN order_payments op
    ON oi.order_id = op.order_id
GROUP BY oi.order_id
LIMIT 5;

--Q6.Find orders where payments differ from price + freight by more than 1.00.
select * from order_items limit 10;

SELECT
    o.order_id,
    SUM(oi.price + oi.freight_value) AS order_total,
    SUM(op.payment_value) AS payment_total,
    ROUND(
        ABS(
            SUM(op.payment_value)
            - SUM(oi.price + oi.freight_value)
        ),
        2
    ) AS difference
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN order_payments op
    ON o.order_id = op.order_id
GROUP BY o.order_id
HAVING ABS(
    SUM(op.payment_value)
    - SUM(oi.price + oi.freight_value)
) > 1.00;







