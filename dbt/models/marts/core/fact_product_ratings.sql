{{ config(unique_key='rating_id', incremental_strategy='merge') }}

select
    to_hex(
    md5(
        to_utf8(
            cast(customer_number as varchar)
            || '|'
            || product_code
            || '|'
            || cast(rating_timestamp as varchar)
            )
        )
    ) as rating_id,
    customer_number,
    product_code,
    product_rating,
    rating_timestamp,
    current_timestamp as dbt_updated_at
from {{ ref('stg_ratings') }} o

{% if is_incremental() and var('processing_date', '') %}

where o.processing_date = '{{ var("processing_date") }}'

{% endif %}

