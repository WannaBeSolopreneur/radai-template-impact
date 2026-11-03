-- After the launch only. Studies with no AI impression are not in the stack.
select
    customer_id,
    coalesce(modality, 'All') as modality,
    specialty,
    ai_impression_status,
    count(*) as n_studies
from {{ ref('fct_studies_metric') }}
where customer_id = '{{ var("customer_id") }}'
    and period = 'after'
    and ai_impression_status is not null
group by grouping sets (
    (customer_id, modality, specialty, ai_impression_status),
    (customer_id, specialty, ai_impression_status)
)
