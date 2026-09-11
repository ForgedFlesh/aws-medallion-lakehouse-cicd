{{ config(unique_key='product_code', incremental_strategy='merge') }}

select
    product_code,
    product_name,
    product_line,
    product_vendor,
    quantity_in_stock,
    buy_price,
    msrp,
    current_timestamp as dbt_updated_at
from {{ ref('stg_products') }}

{% if is_incremental() and var('processing_date', '') %}

where processing_date = '{{ var("processing_date") }}'

{% endif %}
