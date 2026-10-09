with source as (
    select * from {{ source('olist', 'order_reviews') }}
)

-- Duplicate review_id rows are kept here on purpose: the warn-level unique test on
-- review_id flags them, and int_order_reviews_latest resolves them (data_quality_log #7, #8).
select
    trim(review_id)                                         as review_id,
    trim(order_id)                                          as order_id,
    trim(review_score)::int                                 as review_score,
    nullif(trim(review_comment_title), '')                  as review_comment_title,
    nullif(trim(review_comment_message), '')                as review_comment_message,
    nullif(trim(review_creation_date), '')::timestamp       as review_created_at,
    nullif(trim(review_answer_timestamp), '')::timestamp    as review_answered_at
from source
