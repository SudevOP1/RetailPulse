-- Sellers with >= 20 delivered orders. A seller-order is one (seller, order) pair, so an order
-- with two sellers counts once for each. Tier rule (docs/kpi_definitions.md):
--   C = worst late-rate decile, or 1-star rate >= 2x the marketplace rate
--   A = top 20% by GMV (gmv_percent_rank >= 0.8) and late rate <= median scorecard seller
--   B = everyone else
with seller_orders as (
    select
        i.seller_key,
        i.order_id,
        sum(i.price)                                                    as gmv,
        bool_or(o.is_late)                                              as is_late,
        max(o.review_score)                                             as review_score,
        max(o.delivery_days)                                            as delivery_days
    from {{ ref('fact_order_items') }} as i
    inner join {{ ref('fact_orders') }} as o
        on i.order_id = o.order_id
    where o.is_delivered
    group by i.seller_key, i.order_id
),

marketplace as (
    select
        count(*) filter (where is_late)::numeric / count(is_late)       as late_rate,
        count(*) filter (where review_score = 1)::numeric
            / count(review_score)                                       as one_star_rate
    from seller_orders
),

sellers as (
    select
        seller_key,
        count(*)                                                        as orders,
        sum(gmv)                                                        as gmv,
        count(*) filter (where is_late)                                 as late_orders,
        count(is_late)                                                  as orders_with_delivery_date,
        count(*) filter (where is_late)::numeric / nullif(count(is_late), 0) as late_rate,
        avg(review_score)                                               as avg_review,
        count(*) filter (where review_score = 1)::numeric
            / nullif(count(review_score), 0)                            as one_star_rate,
        avg(delivery_days)                                              as avg_delivery_days
    from seller_orders
    group by seller_key
    having count(*) >= 20
),

median_late as (
    select percentile_cont(0.5) within group (order by late_rate) as late_rate
    from sellers
),

ranked as (
    select
        *,
        percent_rank() over (order by gmv)                              as gmv_percent_rank,
        ntile(10) over (order by late_rate, seller_key)                 as late_decile
    from sellers
)

select
    r.seller_key,
    ds.state                                                            as seller_state,
    ds.region                                                           as seller_region,
    r.orders,
    r.gmv,
    r.late_orders,
    r.orders_with_delivery_date,
    round(r.late_rate, 4)                                               as late_rate,
    round(r.avg_review, 3)                                              as avg_review,
    round(r.one_star_rate, 4)                                           as one_star_rate,
    round(r.avg_delivery_days, 2)                                       as avg_delivery_days,
    round(r.gmv_percent_rank::numeric, 4)                               as gmv_percent_rank,
    r.late_decile,
    case
        when r.late_decile = 10 or r.one_star_rate >= 2 * m.one_star_rate   then 'C'
        when r.gmv_percent_rank >= 0.8 and r.late_rate <= ml.late_rate      then 'A'
        else 'B'
    end                                                                 as tier,
    round(m.late_rate, 4)                                               as marketplace_late_rate,
    round(m.one_star_rate, 4)                                           as marketplace_one_star_rate,
    round(ml.late_rate::numeric, 4)                                     as median_seller_late_rate
from ranked as r
cross join marketplace as m
cross join median_late as ml
left join {{ ref('dim_seller') }} as ds
    on r.seller_key = ds.seller_key
