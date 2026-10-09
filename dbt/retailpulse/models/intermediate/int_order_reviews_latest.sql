-- One review per order: the most recently answered one. Resolves the 547 orders with
-- several reviews (data_quality_log #8); the duplicate review_id rows (#7) then no longer
-- inflate any order-level metric.
with reviews as (
    select * from {{ ref('stg_olist__reviews') }}
),

ranked as (
    select
        *,
        row_number() over (
            partition by order_id
            order by review_answered_at desc, review_created_at desc, review_id
        ) as review_rank
    from reviews
)

select
    order_id,
    review_id,
    review_score,
    review_comment_title,
    review_comment_message,
    review_comment_message is not null as has_review_comment,
    review_created_at,
    review_answered_at
from ranked
where review_rank = 1
