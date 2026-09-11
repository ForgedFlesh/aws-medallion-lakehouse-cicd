with source_rows as (
    select *
    from {{ source('curated', 'orders') }}
    where ordernumber is not null
), ranked as (
    select
        source_rows.*,
        row_number() over (
            partition by ordernumber
            order by processing_date desc, ingest_ts desc
        ) as rn
    from source_rows
), deduplicated as (
    select *
    from ranked
    where rn = 1
)
select
    cast(ordernumber as bigint) as order_number,
    cast(customernumber as bigint) as customer_number,
    cast(orderdate as date) as order_date,
    cast(requireddate as date) as required_date,
    cast(shippeddate as date) as shipped_date,
    upper(trim(status)) as order_status,
    cast(ingest_ts as timestamp) as ingest_ts,
    processing_date,
    source
from deduplicated
