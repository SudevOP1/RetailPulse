-- Monthly KPIs by purchase month, trend window Jan 2017 - Aug 2018 (data_quality_log #25).
-- Definitions (docs/kpi_definitions.md): orders = all orders placed (any status);
-- GMV / AOV / customers / freight / reviews use delivered orders only; on-time rate uses
-- delivered orders with a delivered date (is_late not null).
with orders as (
    select * from {{ ref('fact_orders') }}
),

dates as (
    select date_key, year_month, month_start from {{ ref('dim_date') }}
),

monthly as (
    select
        d.year_month,
        d.month_start,
        count(*)                                                        as orders,
        count(*) filter (where o.is_delivered)                          as delivered_orders,
        sum(o.items_value) filter (where o.is_delivered)                as gmv,
        sum(o.freight_value) filter (where o.is_delivered)              as freight,
        count(distinct o.customer_key) filter (where o.is_delivered)    as customers,
        count(*) filter (where o.is_late = false)                       as on_time_orders,
        count(o.is_late)                                                as orders_with_delivery_date,
        avg(o.review_score) filter (where o.is_delivered)               as avg_review,
        count(*) filter (where o.is_delivered and o.review_score = 1)   as one_star_reviews,
        count(o.review_score) filter (where o.is_delivered)             as reviews
    from orders as o
    inner join dates as d
        on o.purchase_date_key = d.date_key
    where d.month_start between date '2017-01-01' and date '2018-08-01'
    group by d.year_month, d.month_start
)

select
    year_month,
    month_start,
    orders,
    delivered_orders,
    gmv,
    round(gmv / nullif(delivered_orders, 0), 2)                         as aov,
    customers,
    round(on_time_orders::numeric / nullif(orders_with_delivery_date, 0), 4) as on_time_rate,
    round(avg_review, 3)                                                as avg_review,
    round(one_star_reviews::numeric / nullif(reviews, 0), 4)            as one_star_rate,
    round(freight / nullif(gmv + freight, 0), 4)                        as freight_share,
    round(gmv / lag(gmv) over (order by month_start) - 1, 4)            as gmv_mom,
    round(orders::numeric / lag(orders, 12) over (order by month_start) - 1, 4) as orders_yoy
from monthly
