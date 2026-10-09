-- Delivery economics by customer state (27 UFs), delivered orders only.
-- freight_share = freight / (item price + freight); late_rate over orders with a delivered date.
select
    customer_state,
    customer_region,
    count(*)                                                            as orders,
    sum(items_value)                                                    as gmv,
    sum(freight_value)                                                  as freight,
    round(sum(freight_value) / nullif(sum(items_value + freight_value), 0), 4) as freight_share,
    round(count(*) filter (where is_late)::numeric / nullif(count(is_late), 0), 4) as late_rate,
    round(avg(delivery_days), 2)                                        as avg_delivery_days,
    round(avg(promised_days) filter (where delivery_days is not null), 2) as avg_promised_days,
    round(avg(review_score), 3)                                         as avg_review
from {{ ref('fact_orders') }}
where is_delivered
group by customer_state, customer_region
