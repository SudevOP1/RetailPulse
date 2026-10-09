with source as (
    select * from {{ source('olist', 'product_category_name_translation') }}
)

select
    lower(trim(product_category_name))          as category_pt,
    lower(trim(product_category_name_english))  as category_en
from source
