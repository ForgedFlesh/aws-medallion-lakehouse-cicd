{{ config(unique_key='customer_number', incremental_strategy='merge') }}

select
    customer_number,
    customer_name,
    contact_first_name,
    contact_last_name,
    phone,
    city,
    state,
    country,
    credit_limit,
    current_timestamp as dbt_updated_at
from {{ ref('stg_customers') }}

{% if is_incremental() and var('processing_date', '') %}

where processing_date = '{{ var("processing_date") }}'

{% endif %}
