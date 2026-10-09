with source as (
    select * from {{ source('olist', 'customers') }}
)

select
    trim(customer_id)                 as customer_id,
    trim(customer_unique_id)          as customer_unique_id,
    trim(customer_zip_code_prefix)    as zip_prefix,  -- text: leading zeros matter
    lower(trim(customer_city))        as city,
    upper(trim(customer_state))       as state
from source
