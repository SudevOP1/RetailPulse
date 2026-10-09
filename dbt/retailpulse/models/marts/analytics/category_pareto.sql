-- Category Pareto on delivered item GMV (item price, no freight). The 'unknown' bucket
-- (610 products with a null category) is excluded, leaving 73 real categories.
-- A = the categories needed to reach 80% of GMV (cumulative share before the row < 80%),
-- B = needed to reach 95%, C = the rest.
with category_gmv as (
    select
        p.category_en,
        p.category_pt,
        count(*)                                                        as items,
        count(distinct i.order_id)                                      as orders,
        sum(i.price)                                                    as gmv
    from {{ ref('fact_order_items') }} as i
    inner join {{ ref('dim_product') }} as p
        on i.product_key = p.product_key
    where i.is_delivered
      and p.category_en <> 'unknown'
    group by p.category_en, p.category_pt
),

ranked as (
    select
        *,
        rank() over (order by gmv desc)                                 as gmv_rank,
        gmv / sum(gmv) over ()                                          as gmv_share,
        sum(gmv) over (
            order by gmv desc, category_en
            rows between unbounded preceding and current row
        ) / sum(gmv) over ()                                            as cum_share
    from category_gmv
)

select
    category_en,
    category_pt,
    items,
    orders,
    gmv,
    gmv_rank,
    round(gmv_share, 4)                                                 as gmv_share,
    round(cum_share, 4)                                                 as cum_share,
    case
        when cum_share - gmv_share < 0.80 then 'A'
        when cum_share - gmv_share < 0.95 then 'B'
        else 'C'
    end                                                                 as abc_class
from ranked
