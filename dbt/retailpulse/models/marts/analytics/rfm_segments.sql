-- One row per customer with >= 1 delivered order. Recency is measured from the day after
-- the last delivered purchase in the data. ~97% of customers bought once, so NTILE(5) on
-- frequency is meaningless: frequency is a flag (>= 2 delivered orders) instead.
with delivered as (
    select customer_key, purchased_at, items_value
    from {{ ref('fact_orders') }}
    where is_delivered
),

as_of as (
    select max(purchased_at)::date + 1 as as_of_date from delivered
),

customers as (
    select
        d.customer_key,
        max(d.purchased_at)::date                                       as last_order_date,
        a.as_of_date - max(d.purchased_at)::date                        as recency_days,
        count(*)                                                        as frequency,
        sum(d.items_value)                                              as monetary
    from delivered as d
    cross join as_of as a
    group by d.customer_key, a.as_of_date
),

scored as (
    select
        *,
        ntile(5) over (order by recency_days desc, customer_key)        as r_score,
        ntile(5) over (order by monetary, customer_key)                 as m_score,
        frequency >= 2                                                  as f_flag
    from customers
)

select
    customer_key,
    last_order_date,
    recency_days,
    frequency,
    monetary,
    r_score,
    m_score,
    f_flag,
    case
        when f_flag and r_score >= 3        then 'Champions'
        when f_flag                         then 'Loyal-lapsing'
        when r_score >= 4 and m_score >= 4  then 'New high-value'
        when r_score >= 4                   then 'New/promising'
        when m_score >= 4                   then 'At-risk high-value'
        else 'Hibernating'
    end                                                                 as segment
from scored
