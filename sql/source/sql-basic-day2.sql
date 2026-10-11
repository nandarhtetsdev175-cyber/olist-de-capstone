select * from orders limit 5;

select c.customer_id ,c.customer_state ,o.order_id ,o.order_status  from customers c join orders  o
on c.customer_id  =  o.customer_id

select count(*) from orders o join order_reviews r
on o.order_id  =  r.order_id


select count(*) from orders

select count(1) from order_reviews t 

select count(*) from orders o left join order_reviews r
on o.order_id  =  r.order_id where r.order_id  is null

select 99992 -99441

--Q1.Revenue (SUM of price) by customer_state for delivered orders. Top 10 states.

