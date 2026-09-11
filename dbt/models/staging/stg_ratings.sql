with source_rows as (

    select *
    from {{ source('curated', 'ratings_for_ml') }}

    where customernumber is not null
      and productcode is not null

),  ranked as (
    select
        source_rows.*,
        row_number() over (
            partition by customernumber, productcode, ratingtimestamp
            order by processing_ts desc, ingest_ts desc
        ) as rn
    from source_rows
), deduplicated as (
    select *
    from ranked
    where rn = 1
)
select
    cast(customernumber as bigint) as customer_number,
    trim(productcode) as product_code,
    cast(productrating as integer) as product_rating,
    cast(coalesce(ratingtimestamp, ingest_ts) as timestamp) as rating_timestamp,
    cast(ingest_ts as timestamp) as ingest_ts,
    processing_date,
    source
from deduplicated
