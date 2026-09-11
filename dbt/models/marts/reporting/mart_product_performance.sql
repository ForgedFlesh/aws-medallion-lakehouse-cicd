with sales as (

    select
        product_code,
        sum(quantity_ordered) as units_sold,
        sum(gross_amount) as gross_sales
    from {{ ref('fact_order_items') }}
    group by product_code

), ratings as (

    select
        product_code,
        count(*) as rating_count,
        avg(cast(product_rating as decimal(10,2))) as average_rating
    from {{ ref('fact_product_ratings') }}
    group by product_code

)

select
    p.product_code,
    p.product_name,
    p.product_line,
    p.product_vendor,
    coalesce(s.units_sold, 0) as units_sold,
    coalesce(s.gross_sales, 0) as gross_sales,
    coalesce(r.rating_count, 0) as rating_count,
    r.average_rating
from {{ ref('dim_products') }} p
left join sales s
    on p.product_code = s.product_code
left join ratings r
    on p.product_code = r.product_code