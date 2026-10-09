with source as (
    select * from {{ source('olist', 'order_payments') }}
)

select
    trim(order_id)                          as order_id,
    trim(payment_sequential)::int           as payment_sequential,
    lower(trim(payment_type))               as payment_type,
    trim(payment_installments)::int         as payment_installments,
    trim(payment_value)::numeric(10, 2)     as payment_value
from source
