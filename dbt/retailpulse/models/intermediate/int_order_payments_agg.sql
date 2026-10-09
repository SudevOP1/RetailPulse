-- One row per order with payments. payment_type_primary = the type carrying the largest value.
with payments as (
    select * from {{ ref('stg_olist__payments') }}
),

ranked as (
    select
        order_id,
        payment_type,
        row_number() over (
            partition by order_id
            order by payment_value desc, payment_sequential
        ) as value_rank
    from payments
),

totals as (
    select
        order_id,
        sum(payment_value)          as payment_value,
        max(payment_installments)   as max_installments,
        count(*)                    as payments_count
    from payments
    group by order_id
)

select
    t.order_id,
    t.payment_value,
    t.max_installments,
    t.payments_count,
    r.payment_type as payment_type_primary
from totals as t
inner join ranked as r
    on t.order_id = r.order_id
   and r.value_rank = 1
