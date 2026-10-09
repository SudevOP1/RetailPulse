-- One row per order that has items (orders with no items are absent; fact_orders zero-fills).
with items as (
    select * from {{ ref('stg_olist__order_items') }}
)

select
    order_id,
    count(*)                    as items_count,
    count(distinct seller_id)   as sellers_count,
    sum(price)                  as items_value,
    sum(freight_value)          as freight_value
from items
group by order_id
