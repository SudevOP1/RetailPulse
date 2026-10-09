-- One row per order (99,441). Shared definitions (CLAUDE.md):
--   late = delivered_customer_at::date > estimated_delivery_at::date, only for status
--   'delivered' with a delivered date; null otherwise. Review = latest per order.
with orders as (
    select * from {{ ref('stg_olist__orders') }}
),

customers as (
    select * from {{ ref('stg_olist__customers') }}
),

items as (
    select * from {{ ref('int_order_items_agg') }}
),

payments as (
    select * from {{ ref('int_order_payments_agg') }}
),

reviews as (
    select * from {{ ref('int_order_reviews_latest') }}
),

regions as (
    select * from {{ ref('state_region') }}
),

joined as (
    select
        o.order_id,
        c.customer_unique_id                                as customer_key,
        to_char(o.purchased_at, 'YYYYMMDD')::int            as purchase_date_key,
        o.order_status,
        o.purchased_at,
        o.approved_at,
        o.delivered_carrier_at,
        o.delivered_customer_at,
        o.estimated_delivery_at,
        coalesce(i.items_count, 0)                          as items_count,
        coalesce(i.sellers_count, 0)                        as sellers_count,
        coalesce(i.items_value, 0)                          as items_value,
        coalesce(i.freight_value, 0)                        as freight_value,
        p.payment_value,
        p.payment_type_primary,
        p.max_installments,
        o.order_status = 'delivered'                        as is_delivered,
        o.order_status = 'delivered'
            and o.delivered_customer_at is not null         as has_delivery_date,
        r.review_score,
        r.has_review_comment,
        c.state                                             as customer_state,
        rg.region                                           as customer_region
    from orders as o
    inner join customers as c
        on o.customer_id = c.customer_id
    left join items as i
        on o.order_id = i.order_id
    left join payments as p
        on o.order_id = p.order_id
    left join reviews as r
        on o.order_id = r.order_id
    left join regions as rg
        on c.state = rg.state
)

select
    order_id,
    customer_key,
    purchase_date_key,
    order_status,
    purchased_at,
    approved_at,
    delivered_carrier_at,
    delivered_customer_at,
    estimated_delivery_at,
    items_count,
    sellers_count,
    items_value,
    freight_value,
    items_value + freight_value                                         as order_value,
    payment_value,
    payment_type_primary,
    max_installments,
    is_delivered,
    case when has_delivery_date then
        round((extract(epoch from delivered_customer_at - purchased_at) / 86400)::numeric, 2)
    end                                                                 as delivery_days,
    round((extract(epoch from estimated_delivery_at - purchased_at) / 86400)::numeric, 2)
                                                                        as promised_days,
    case when has_delivery_date then
        delivered_customer_at::date - estimated_delivery_at::date
    end                                                                 as days_late,
    case when has_delivery_date then
        delivered_customer_at::date > estimated_delivery_at::date
    end                                                                 as is_late,
    review_score,
    review_score = 1                                                    as is_one_star,
    has_review_comment,
    customer_state,
    customer_region
from joined
