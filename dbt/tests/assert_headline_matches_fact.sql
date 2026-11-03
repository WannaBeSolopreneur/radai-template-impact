select 'tat_before'
from {{ ref('mart_headline') }} as headline
where abs(
    headline.raw_before_minutes - (
        select median(turnaround_minutes)
        from {{ ref('fct_studies_metric') }}
        where period = 'before'
    )
) > 0.01

union all

select 'tat_after'
from {{ ref('mart_headline') }} as headline
where abs(
    headline.raw_after_minutes - (
        select median(turnaround_minutes)
        from {{ ref('fct_studies_metric') }}
        where period = 'after'
    )
) > 0.01

union all

select 'words_after'
from {{ ref('mart_headline') }} as headline
where abs(
    headline.median_words_after - (
        select median(words_dictated)
        from {{ ref('fct_studies_metric') }}
        where period = 'after'
    )
) > 0.01

union all

select 'usage_after'
from {{ ref('mart_headline') }} as headline
where abs(
    headline.template_usage_after - (
        select avg(used_template)
        from {{ ref('fct_studies_metric') }}
        where period = 'after'
    )
) > 0.0001

union all

select 'ai_after'
from {{ ref('mart_headline') }} as headline
where abs(
    headline.ai_acceptance_after - (
        select sum(is_ai_accepted) * 1.0 / nullif(sum(is_ai_scored), 0)
        from {{ ref('fct_studies_metric') }}
        where period = 'after'
    )
) > 0.0001

union all

select 'headline_vs_change'
from {{ ref('mart_headline') }} as headline
inner join {{ ref('mart_case_mix_change') }} as change
    on headline.customer_id = change.customer_id
where abs(headline.adjusted_change_minutes - change.adjusted_change_minutes) > 0.001
    or abs(headline.adjusted_report_change_minutes - change.adjusted_report_change_minutes) > 0.001
    or abs(headline.raw_change_minutes - change.raw_change_minutes) > 0.001
