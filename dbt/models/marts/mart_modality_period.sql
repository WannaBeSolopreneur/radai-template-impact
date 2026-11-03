-- Medians inside modality and period. modality All rolls the mix back up.
-- period all is the whole metric window, used as the group line on the site chart.
select
    customer_id,
    coalesce(modality, 'All') as modality,
    coalesce(period, 'all') as period,
    count(*) as n_studies,
    median(turnaround_minutes) as median_turnaround_minutes,
    median(time_on_report_minutes) as median_time_on_report_minutes,
    median(words_dictated) as median_words,
    avg(used_template) as template_usage_rate,
    case
        when sum(is_ai_scored) = 0 then null
        else sum(is_ai_accepted) * 1.0 / sum(is_ai_scored)
    end as ai_acceptance_rate,
    case when count(*) < {{ var("min_n") }} then 1 else 0 end as too_few_studies
from {{ ref('fct_studies_metric') }}
where customer_id = '{{ var("customer_id") }}'
group by grouping sets (
    (customer_id, modality, period),
    (customer_id, period),
    (customer_id, modality),
    (customer_id)
)
