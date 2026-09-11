{{ config(unique_key='order_item_id', incremental_strategy='merge') }}

select
    to_hex(
    md5(
        to_utf8(
            cast(d.order_number as varchar)
            || '|'
            || cast(d.order_line_number as varchar)
            )
        )
    ) as order_item_id,
    d.order_number,
    d.order_line_number,
    o.customer_number,
    d.product_code,
    cast(
    year(o.order_date) * 10000
    + month(o.order_date) * 100
    + day(o.order_date)
    as integer
    ) as order_date_key, 
    o.order_date,
    o.order_status,
    d.quantity_ordered,
    d.price_each,
    d.gross_amount,
    current_timestamp as dbt_updated_at
from {{ ref('stg_orderdetails') }} d

join {{ ref('stg_orders') }} o
    on d.order_number = o.order_number

{% if is_incremental() and var('processing_date', '') %}

where
    d.processing_date = '{{ var("processing_date") }}'
    or o.processing_date = '{{ var("processing_date") }}'

{% endif %}
