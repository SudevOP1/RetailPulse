-- Payments should equal items + freight. Interest on instalments and vouchers make some
-- orders differ, so this warns on any mismatch > R$1 and only errors if it reaches 1%
-- of orders (994 of 99,441). Includes the 1 order with no payment row.
{{ config(
    severity='error',
    warn_if='>0',
    error_if='>994',
    store_failures=true
) }}

select
    order_id,
    order_status,
    order_value,
    payment_value,
    coalesce(payment_value, 0) - order_value as diff
from {{ ref('fact_orders') }}
where items_count > 0
  and abs(coalesce(payment_value, 0) - order_value) > 1.0
