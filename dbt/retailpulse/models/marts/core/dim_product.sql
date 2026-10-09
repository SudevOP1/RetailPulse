select
    product_id                              as product_key,
    category_pt,
    category_en,
    weight_g,
    length_cm * height_cm * width_cm        as volume_cm3,
    photos_qty,
    name_length,
    description_length
from {{ ref('stg_olist__products') }}
