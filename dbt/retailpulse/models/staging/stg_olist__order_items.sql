with source as (
    select * from {{ source('olist', 'order_items') }}
)

select
    trim(order_id)                              as order_id,
    trim(order_item_id)::int                    as order_item_id,
    trim(product_id)                            as product_id,
    trim(seller_id)                             as seller_id,
    nullif(trim(shipping_limit_date), '')::timestamp as shipping_limit_at,
    trim(price)::numeric(10, 2)                 as price,
    trim(freight_value)::numeric(10, 2)         as freight_value
from source
