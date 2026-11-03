-- Every mart is one customer. The other customer is real upstream, and absent here.

select customer_id from {{ ref('fct_studies') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('fct_studies_metric') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('dim_customer') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('dim_site') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('dim_radiologist') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_headline') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_case_mix_change') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_case_mix_weights') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_modality_period') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_weekly_turnaround') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_site_turnaround') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_heatmap') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_modality_box') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_ai_specialty') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select customer_id from {{ ref('mart_partial_period') }}
where customer_id <> '{{ var("customer_id") }}'

union all

select 'redcedar_missing'
where (
    select count(*)
    from {{ ref('int_studies') }}
    where customer_id = 'cust_redcedar'
        and is_test_fixture = 0
) < 1000

union all

select 'northbay_missing_upstream'
where (
    select count(*)
    from {{ ref('int_studies') }}
    where customer_id = '{{ var("customer_id") }}'
        and is_test_fixture = 0
) < 20000
