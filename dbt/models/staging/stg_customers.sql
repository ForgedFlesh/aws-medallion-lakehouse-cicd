with source_rows as (
    select *
    from {{ source('curated', 'customers') }}
    where customernumber is not null
), ranked as (
    select
        source_rows.*,
        row_number() over (
            partition by customernumber
            order by processing_date desc, ingest_ts desc
        ) as rn
    from source_rows
), deduplicated as (
    select *
    from ranked
    where rn = 1
)
select
    cast(customernumber as bigint) as customer_number,
    trim(customername) as customer_name,
    trim(contactfirstname) as contact_first_name,
    trim(contactlastname) as contact_last_name,
    trim(phone) as phone,
    trim(city) as city,
    trim(state) as state,
    trim(country) as country,
    cast(creditlimit as decimal(18,2)) as credit_limit,
    cast(ingest_ts as timestamp) as ingest_ts,
    processing_date,
    source
from deduplicated
