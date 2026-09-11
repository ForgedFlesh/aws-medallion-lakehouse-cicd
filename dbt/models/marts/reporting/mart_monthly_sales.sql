select
    cast(year(f.order_date) as integer) as sales_year,
    cast(month(f.order_date) as integer) as sales_month,
    count(distinct f.order_number) as order_count,
    sum(f.quantity_ordered) as units_sold,
    sum(f.gross_amount) as gross_sales,
    avg(f.gross_amount) as average_order_line_amount
from {{ ref('fact_order_items') }} f
group by 1, 2
