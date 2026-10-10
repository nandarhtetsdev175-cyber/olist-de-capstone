select * from raw.orders limit 10;

select order_id,order_status  as status from orders limit 10;

select distinct order_status from orders;


select order_id,order_status  as status  from orders
where order_status = 'delivered';

select order_id,order_status  as status  from orders
where order_status <>'canceled';


select * from customers c limit 10;

select distinct customer_state from customers c limit 10;

select customer_id, customer_state from customers
where customer_state  in ('SP','SC','MG');

select * from order_items where price  between 10 and 50;

select * from customers where customer_city like '%sao';

