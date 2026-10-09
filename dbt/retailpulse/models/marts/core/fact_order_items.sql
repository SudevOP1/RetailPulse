-- One row per order item (112,650). Order-level attributes (status, lateness, review)
-- come from fact_orders so both facts share one definition of each.
with items as (
    select * from {{ ref('stg_olist__order_items') }}
),

orders as (
    select * from {{ ref('fact_orders') }}
)

select
    i.order_id,
    i.order_item_id,
    i.product_id            as product_key,
    i.seller_id             as seller_key,
    o.customer_key,
    o.purchase_date_key,
    i.price,
    i.freight_value,
    i.shipping_limit_at,
    o.order_status,
    o.is_delivered,
    o.is_late,
    o.review_score
from items as i
inner join orders as o
    on i.order_id = o.order_id
