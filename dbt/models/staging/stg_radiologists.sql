select
    radiologist_id,
    customer_id,
    site_id,
    radiologist_label
from {{ source('raw', 'radiologists') }}
