select 'northbay'
from {{ ref('stg_generation_meta') }} as meta
where (
    select count(*)
    from {{ ref('int_studies') }}
    where customer_id = meta.customer_id
        and is_test_fixture = 0
) <> meta.n_northbay_studies

union all

select 'redcedar'
from {{ ref('stg_generation_meta') }} as meta
where (
    select count(*)
    from {{ ref('int_studies') }}
    where customer_id = 'cust_redcedar'
        and is_test_fixture = 0
) <> meta.n_redcedar_studies

union all

select 'dim_customer_rows'
where (select count(*) from {{ ref('dim_customer') }}) <> 1
