with source_rows as (
    select *
    from {{ source('curated', 'orderdetails') }}
    where ordernumber is not null and productcode is not null
), ranked as (
    select
        source_rows.*,
        row_number() over (
            partition by ordernumber, orderlinenumber
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
    trim(productcode) as product_code,
    cast(quantityordered as integer) as quantity_ordered,
    cast(priceeach as decimal(18,2)) as price_each,
    cast(orderlinenumber as integer) as order_line_number,
    cast(quantityordered as decimal(18,2)) * cast(priceeach as decimal(18,2)) as gross_amount,
    cast(ingest_ts as timestamp) as ingest_ts,
    processing_date,
    source
from deduplicated
