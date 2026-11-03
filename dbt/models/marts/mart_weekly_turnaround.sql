select
    customer_id,
    week_start,
    coalesce(modality, 'All') as modality,
    count(*) as n_studies,
    median(turnaround_minutes) as median_turnaround_minutes,
    case when count(*) < {{ var("min_n") }} then 1 else 0 end as too_few_studies
from {{ ref('fct_studies_metric') }}
where customer_id = '{{ var("customer_id") }}'
group by grouping sets (
    (customer_id, week_start, modality),
    (customer_id, week_start)
)
