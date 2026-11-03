-- Metric population. The last two days are still loading, so they stay off this table.
select *
from {{ ref('fct_studies') }}
where customer_id = '{{ var("customer_id") }}'
    and is_partial_period = 0
