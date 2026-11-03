select
    site_id,
    customer_id,
    site_name,
    size_band,
    sort_order
from {{ source('raw', 'sites') }}
