with source as (
    select * from {{ source('olist', 'geolocation') }}
)

select
    trim(geolocation_zip_code_prefix)       as zip_prefix,
    trim(geolocation_lat)::double precision   as lat,
    trim(geolocation_lng)::double precision   as lng,
    lower(trim(geolocation_city))           as city,
    upper(trim(geolocation_state))          as state
from source
