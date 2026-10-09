with source as (
    select * from {{ source('olist', 'sellers') }}
)

select
    trim(seller_id)                 as seller_id,
    trim(seller_zip_code_prefix)    as zip_prefix,  -- text: leading zeros matter
    lower(trim(seller_city))        as city,
    upper(trim(seller_state))       as state
from source
