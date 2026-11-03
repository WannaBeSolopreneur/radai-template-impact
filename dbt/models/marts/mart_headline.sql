with rates as (
    select
        customer_id,
        count(*) as n_studies,
        sum(case when period = 'before' then 1 else 0 end) as n_before,
        sum(case when period = 'after' then 1 else 0 end) as n_after,
        avg(case when period = 'before' then used_template end) as template_usage_before,
        avg(case when period = 'after' then used_template end) as template_usage_after,
        sum(case when period = 'after' and used_template = 1 then 1 else 0 end) as template_usage_after_n,
        case
            when sum(case when period = 'before' then is_ai_scored else 0 end) = 0 then null
            else sum(case when period = 'before' then is_ai_accepted else 0 end) * 1.0
                / sum(case when period = 'before' then is_ai_scored else 0 end)
        end as ai_acceptance_before,
        case
            when sum(case when period = 'after' then is_ai_scored else 0 end) = 0 then null
            else sum(case when period = 'after' then is_ai_accepted else 0 end) * 1.0
                / sum(case when period = 'after' then is_ai_scored else 0 end)
        end as ai_acceptance_after,
        sum(case when period = 'after' then is_ai_scored else 0 end) as ai_scored_after_n,
        median(case when period = 'before' then words_dictated end) as median_words_before,
        median(case when period = 'after' then words_dictated end) as median_words_after,
        sum(case when modality = 'MRI' and period = 'before' then 1 else 0 end) * 1.0
            / nullif(sum(case when period = 'before' then 1 else 0 end), 0) as mri_share_before,
        sum(case when modality = 'MRI' and period = 'after' then 1 else 0 end) * 1.0
            / nullif(sum(case when period = 'after' then 1 else 0 end), 0) as mri_share_after
    from {{ ref('fct_studies_metric') }}
    where customer_id = '{{ var("customer_id") }}'
    group by 1
),

partial as (
    select
        customer_id,
        count(*) as partial_studies
    from {{ ref('fct_studies') }}
    where customer_id = '{{ var("customer_id") }}'
        and is_partial_period = 1
    group by 1
),

meta as (
    select
        launch_at,
        partial_start,
        as_of,
        seed,
        bootstrap_draws,
        window_start,
        window_end
    from {{ ref('stg_generation_meta') }}
)

select
    rates.customer_id,
    customers.customer_name,
    rates.n_studies,
    rates.n_before,
    rates.n_after,
    partial.partial_studies,
    change.raw_before_minutes,
    change.raw_after_minutes,
    change.raw_change_minutes,
    change.adjusted_before_minutes,
    change.adjusted_after_minutes,
    change.adjusted_change_minutes,
    change.adjusted_report_before_minutes,
    change.adjusted_report_after_minutes,
    change.adjusted_report_change_minutes,
    rates.template_usage_before,
    rates.template_usage_after,
    rates.template_usage_after_n,
    rates.ai_acceptance_before,
    rates.ai_acceptance_after,
    rates.ai_scored_after_n,
    rates.median_words_before,
    rates.median_words_after,
    rates.mri_share_before,
    rates.mri_share_after,
    meta.launch_at,
    meta.partial_start,
    meta.as_of,
    meta.seed,
    meta.bootstrap_draws,
    meta.window_start,
    meta.window_end
from rates
inner join {{ ref('mart_case_mix_change') }} as change
    on rates.customer_id = change.customer_id
inner join partial
    on rates.customer_id = partial.customer_id
inner join {{ ref('dim_customer') }} as customers
    on rates.customer_id = customers.customer_id
cross join meta
where rates.customer_id = '{{ var("customer_id") }}'
