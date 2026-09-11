with source_rows as (

    select *
    from {{ source('curated', 'products') }}
    where productcode is not null

), ranked as (

    select
        source_rows.*,
        row_number() over (
            partition by productcode
            order by processing_date desc, ingest_ts desc
        ) as row_rank
    from source_rows

), deduplicated as (

    select *
    from ranked
    where row_rank = 1

)

select
    trim(productcode) as product_code,
    trim(productname) as product_name,
    trim(productline) as product_line,
    trim(productvendor) as product_vendor,
    cast(quantityinstock as integer) as quantity_in_stock,
    cast(buyprice as decimal(18,2)) as buy_price,
    cast(msrp as decimal(18,2)) as msrp,
    cast(ingest_ts as timestamp) as ingest_ts,
    processing_date,
    source
from deduplicated