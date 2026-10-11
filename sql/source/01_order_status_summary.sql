--Q1 How many customers are there in each state? Show the top 5 states.---
--top 5 states,.limit 
--Group by 
select count(*) as customer ,customer_state from customers 
group by customer_state 
order by customer desc
limit 5;

-------Q2 How many distinct real customers (customer_unique_id) are there?--
select * from customers;

SELECT COUNT(DISTINCT customer_unique_id ) AS distinct_customers
FROM customers;

---Q3 Which payment_type is used most, and what is its total payment_value?--
select payment_type ,count(*) payment,SUM(payment_value) AS total_payment_value
from order_payments 
group by payment_type
order by payment desc;

---Q4 Count reviews for each score (1-5) and find the average score.

select *   from order_reviews 

	select review_score ,count(*) as review_count,round(avg(review_score)) as average_score  from order_reviews 
	group by review_score
	order by review_score ;


-----5.Sellers by state: which states have more than 50 sellers?--
select * from sellers limit 5;


select count(*) as sellers,seller_state from sellers 
group by seller_state 
having count(*) > 50
order by sellers desc;

------Q5..Average price and freight per order item, rounded to 2 decimals.
--AVG,ROUND
select * from order_items oi 
select round(avg(price) ,2) as average_price, round(avg(freight_value ) ,2) as average_freight from order_items

select round(avg(price) ,2) as average_price, round(avg(freight_value ) ,2) as average_freight ,order_id from order_items
group by order_id

