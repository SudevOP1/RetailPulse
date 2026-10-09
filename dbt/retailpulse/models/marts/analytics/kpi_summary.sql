-- One-row headline KPIs over the whole dataset (not only the trend window).
-- Repeat-purchase rate = customers (customer_unique_id) with >= 2 delivered orders
-- / customers with >= 1 delivered order.
with orders as (
    select * from {{ ref('fact_orders') }}
),

customer_orders as (
    select
        customer_key,
        count(*) filter (where is_delivered)    as delivered_orders
    from orders
    group by customer_key
),

customers as (
    select
        count(*) filter (where delivered_orders >= 1)   as customers,
        count(*) filter (where delivered_orders >= 2)   as repeat_customers
    from customer_orders
),

totals as (
    select
        count(*)                                                    as orders,
        count(*) filter (where is_delivered)                        as delivered_orders,
        sum(items_value) filter (where is_delivered)                as gmv,
        sum(freight_value) filter (where is_delivered)              as freight,
        count(*) filter (where is_late)                             as late_orders,
        count(is_late)                                              as orders_with_delivery_date,
        avg(review_score) filter (where is_delivered)               as avg_review,
        count(*) filter (where is_delivered and review_score = 1)   as one_star_reviews,
        count(review_score) filter (where is_delivered)             as reviews
    from orders
)

select
    t.orders,
    t.delivered_orders,
    t.gmv,
    round(t.gmv / t.delivered_orders, 2)                                as aov,
    round(t.freight / (t.gmv + t.freight), 4)                           as freight_share,
    c.customers,
    c.repeat_customers,
    round(c.repeat_customers::numeric / c.customers, 4)                 as repeat_purchase_rate,
    t.late_orders,
    t.orders_with_delivery_date,
    round(t.late_orders::numeric / t.orders_with_delivery_date, 4)      as late_share,
    round(t.avg_review, 3)                                              as avg_review,
    round(t.one_star_reviews::numeric / t.reviews, 4)                   as one_star_rate
from totals as t
cross join customers as c
