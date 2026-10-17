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
---share ,% => (items matching the conditions / Total Items ) * ,use condition => case when 
select * from order_items limit 10;
select * from orders limit 10;
select distinct customer_state from customers limit 10;
select distinct seller_state  from sellers limit 10;



select count(*) as total_order_items,sum(case when c.customer_state = s.seller_state then 1 else 0 end) as same_state_order_items,
round(100.0*sum(case when c.customer_state = s.seller_state then 1 else 0 end) /count(*),2 ) as same_state_share_percentage
from orders o join customers c on o.customer_id = c.customer_id
join order_items oi  on o.order_id = oi.order_id
join sellers s  on oi.seller_id = s.seller_id;



---Q5.For 5 orders, show item revenue and payment total side by side — without fan-out.---
--SUM ,compare side by side 
select o.order_id,SUM(oi.price +oi.freight_value ) as item_revenue, SUM(op.payment_value ) as payment_total from orders o 
join order_items oi  on o.order_id = oi.order_id 
join order_payments op  on op.order_id  =  o.order_id 
group by o.order_id 
limit 5;




--Q6.Find orders where payments differ from price + freight by more than 1.00.--
--diff -> abs ,price + freight_value from order items
select * from order_items limit 10;

select o.order_id, SUM(oi.price+ oi.freight_value  ) as total_oi, sum(op.payment_value ) as payment_total ,
round(abs(sum(op.payment_value ) - SUM(oi.price+ oi.freight_value  ))) as difference
from orders o 
join order_items oi  on o.order_id = oi.order_id
join order_payments op  on o.order_id = op.order_id
group by o.order_id ,op.payment_value
having abs(sum(op.payment_value ) - SUM(oi.price+ oi.freight_value  )) > 1.00;









