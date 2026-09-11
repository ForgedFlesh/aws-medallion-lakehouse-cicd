{{ config(materialized='table') }}

with dates as (
    select distinct order_date as date_day
    from {{ ref('fact_order_items') }}
    where order_date is not null
)
select
    cast(
        year(date_day) * 10000
        + month(date_day) * 100
        + day(date_day)
        as integer
    ) as date_key,

    date_day,

    cast(year(date_day) as integer) as year_number,

    cast(month(date_day) as integer) as month_number,

    date_format(
        cast(date_day as timestamp),
        '%M'
    ) as month_name,

    cast(quarter(date_day) as integer) as quarter_number,

    cast(
        mod(day_of_week(date_day), 7)
        as integer
    ) as day_of_week_number

from dates
