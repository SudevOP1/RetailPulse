-- One row per real customer (customer_unique_id), not per order-level customer_id
-- (data_quality_log #6). Location = the one on the customer's most recent order.
with customers as (
    select * from {{ ref('stg_olist__customers') }}
),

orders as (
    select * from {{ ref('stg_olist__orders') }}
),

customer_orders as (
    select
        c.customer_unique_id,
        c.zip_prefix,
        c.city,
        c.state,
        o.order_id,
        o.order_status,
        o.purchased_at,
        row_number() over (
            partition by c.customer_unique_id
            order by o.purchased_at desc, o.order_id
        ) as recency_rank
    from customers as c
    inner join orders as o
        on c.customer_id = o.customer_id
),

order_rollup as (
    select
        customer_unique_id,
        min(purchased_at)::date                                 as first_order_date,
        max(purchased_at)::date                                 as last_order_date,
        count(*)                                                as orders_count,
        count(*) filter (where order_status = 'delivered')      as delivered_orders_count
    from customer_orders
    group by customer_unique_id
)

select
    co.customer_unique_id               as customer_key,
    co.zip_prefix,
    co.city,
    co.state,
    sr.region,
    geo.lat,
    geo.lng,
    r.first_order_date,
    r.last_order_date,
    r.orders_count,
    r.delivered_orders_count
from customer_orders as co
inner join order_rollup as r
    on co.customer_unique_id = r.customer_unique_id
left join {{ ref('state_region') }} as sr
    on co.state = sr.state
left join {{ ref('int_zip_geolocation') }} as geo
    on co.zip_prefix = geo.zip_prefix
where co.recency_rank = 1
