with sellers as (
    select * from {{ ref('stg_olist__sellers') }}
),

first_sale as (
    select
        i.seller_id,
        min(o.purchased_at)::date   as first_sale_date
    from {{ ref('stg_olist__order_items') }} as i
    inner join {{ ref('stg_olist__orders') }} as o
        on i.order_id = o.order_id
    group by i.seller_id
)

select
    s.seller_id             as seller_key,
    s.zip_prefix,
    s.city,
    s.state,
    sr.region,
    geo.lat,
    geo.lng,
    fs.first_sale_date
from sellers as s
left join first_sale as fs
    on s.seller_id = fs.seller_id
left join {{ ref('state_region') }} as sr
    on s.state = sr.state
left join {{ ref('int_zip_geolocation') }} as geo
    on s.zip_prefix = geo.zip_prefix
