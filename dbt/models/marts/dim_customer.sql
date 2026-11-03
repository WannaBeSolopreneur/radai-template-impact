select
    customer_id,
    customer_name
from {{ ref('stg_customers') }}
where customer_id = '{{ var("customer_id") }}'
