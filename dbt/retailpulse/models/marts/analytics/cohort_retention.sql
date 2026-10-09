-- Monthly acquisition cohorts. A customer (customer_unique_id) is active in a month if they
-- placed a non-canceled, non-unavailable order that month; cohort = first active month.
with order_months as (
    select
        customer_key,
        date_trunc('month', purchased_at)::date                         as order_month
    from {{ ref('fact_orders') }}
    where order_status not in ('canceled', 'unavailable')
    group by 1, 2
),

cohorts as (
    select
        customer_key,
        order_month,
        min(order_month) over (partition by customer_key)               as cohort_month
    from order_months
),

indexed as (
    select
        cohort_month,
        customer_key,
        ((extract(year from order_month) - extract(year from cohort_month)) * 12
            + extract(month from order_month) - extract(month from cohort_month))::int as month_index
    from cohorts
)

select
    cohort_month,
    to_char(cohort_month, 'YYYY-MM')                                    as cohort_year_month,
    month_index,
    count(distinct customer_key)                                        as active_customers,
    first_value(count(distinct customer_key)) over w                    as cohort_size,
    round(100.0 * count(distinct customer_key)
        / first_value(count(distinct customer_key)) over w, 2)          as retention_pct,
    cohort_month between date '2017-01-01' and date '2018-08-01'        as in_trend_window
from indexed
group by cohort_month, month_index
window w as (partition by cohort_month order by month_index)
