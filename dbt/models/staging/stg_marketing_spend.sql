select
    channel,
    channel_name,
    spend,
    sort_order
from {{ source('raw', 'marketing_spend') }}
