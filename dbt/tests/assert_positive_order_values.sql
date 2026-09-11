select *
from {{ ref('fact_order_items') }}
where quantity_ordered <= 0
   or price_each < 0
   or gross_amount < 0
