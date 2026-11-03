{{ config(materialized='view', schema='spine') }}

-- Calendar for the semantic layer. This is not a customer table, so it has no customer_id.
with digits as (
    select 0 as digit
    union all select 1
    union all select 2
    union all select 3
    union all select 4
    union all select 5
    union all select 6
    union all select 7
    union all select 8
    union all select 9
),

numbers as (
    select ones.digit + 10 * tens.digit + 100 * hundreds.digit as day_offset
    from digits as ones
    cross join digits as tens
    cross join digits as hundreds
)

select {{ date_add_days("cast('2025-11-01' as date)", "day_offset") }} as date_day
from numbers
where day_offset <= 430
