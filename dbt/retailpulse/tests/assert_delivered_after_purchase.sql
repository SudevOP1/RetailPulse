-- Delivered orders must reach the customer at or after purchase. Returns violating orders.
select
    order_id,
    purchased_at,
    delivered_customer_at
from {{ ref('fact_orders') }}
where is_delivered
  and delivered_customer_at < purchased_at
