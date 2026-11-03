-- Fixed mix. The weights are the pre-launch modality shares and they do not move after launch.
select
    customer_id,
    modality,
    n_studies,
    n_studies * 1.0 / sum(n_studies) over (partition by customer_id) as weight
from {{ ref('mart_modality_period') }}
where customer_id = '{{ var("customer_id") }}'
    and period = 'before'
    and modality <> 'All'
