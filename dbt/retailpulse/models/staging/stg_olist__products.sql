-- Staging exception (CLAUDE.md): products join the category translation plus the patch
-- seed so every downstream model gets an English category (data_quality_log #13, #14).
with source as (
    select * from {{ source('olist', 'products') }}
),

translation as (
    select category_pt, category_en from {{ ref('stg_olist__category_translation') }}
    union all
    select
        lower(trim(product_category_name)),
        lower(trim(product_category_name_english))
    from {{ ref('category_translation_patch') }}
),

products as (
    select
        trim(product_id)                                    as product_id,
        lower(nullif(trim(product_category_name), ''))      as category_pt,
        nullif(trim(product_name_lenght), '')::int          as name_length,         -- sic in source
        nullif(trim(product_description_lenght), '')::int   as description_length,  -- sic in source
        nullif(trim(product_photos_qty), '')::int           as photos_qty,
        nullif(trim(product_weight_g), '')::int             as weight_g,
        nullif(trim(product_length_cm), '')::int            as length_cm,
        nullif(trim(product_height_cm), '')::int            as height_cm,
        nullif(trim(product_width_cm), '')::int             as width_cm
    from source
)

select
    p.product_id,
    coalesce(p.category_pt, 'unknown')                      as category_pt,
    -- Null category -> 'unknown'. A category that exists but has no translation stays
    -- null, so the not_null test on dim_product.category_en catches a missing patch.
    case when p.category_pt is null then 'unknown' else t.category_en end as category_en,
    p.name_length,
    p.description_length,
    p.photos_qty,
    p.weight_g,
    p.length_cm,
    p.height_cm,
    p.width_cm
from products as p
left join translation as t
    on p.category_pt = t.category_pt
