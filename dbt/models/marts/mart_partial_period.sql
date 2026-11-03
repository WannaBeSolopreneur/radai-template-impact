select
    customer_id,
    count(*) as partial_studies,
    min(exam_completed_at) as partial_start_observed,
    max(exam_completed_at) as partial_end_observed
from {{ ref('fct_studies') }}
where customer_id = '{{ var("customer_id") }}'
    and is_partial_period = 1
group by 1
