select
    customer_id,
    site_id,
    site_name,
    size_band,
    coalesce(modality, 'All') as modality,
    count(*) as n_studies,
    median(turnaround_minutes) as median_turnaround_minutes,
    case when count(*) < {{ var("min_n") }} then 1 else 0 end as too_few_studies
from {{ ref('fct_studies_metric') }}
where customer_id = '{{ var("customer_id") }}'
group by grouping sets (
    (customer_id, site_id, site_name, size_band, modality),
    (customer_id, site_id, site_name, size_band)
)
