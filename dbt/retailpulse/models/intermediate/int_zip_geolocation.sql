-- One row per zip prefix (~19K instead of ~1M points). Points outside Brazil's bounding
-- box are dropped before averaging (data_quality_log #10, #11).
with geo as (
    select * from {{ ref('stg_olist__geolocation') }}
    where lat between -34 and 6
      and lng between -74 and -34
)

select
    zip_prefix,
    avg(lat)        as lat,
    avg(lng)        as lng,
    count(*)        as points_count
from geo
group by zip_prefix
