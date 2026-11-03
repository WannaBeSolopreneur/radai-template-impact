select
    customer_id,
    modality,
    period,
    count(*) as n_studies,
    percentile_cont(0.10) within group (order by time_on_report_minutes) as p10,
    percentile_cont(0.25) within group (order by time_on_report_minutes) as p25,
    percentile_cont(0.50) within group (order by time_on_report_minutes) as p50,
    percentile_cont(0.75) within group (order by time_on_report_minutes) as p75,
    percentile_cont(0.90) within group (order by time_on_report_minutes) as p90,
    case when count(*) < {{ var("min_n") }} then 1 else 0 end as too_few_studies
from {{ ref('fct_studies_metric') }}
where customer_id = '{{ var("customer_id") }}'
group by 1, 2, 3
