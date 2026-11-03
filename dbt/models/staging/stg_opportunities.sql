select
    opportunity_id,
    account_id,
    prospect_name,
    segment,
    stage,
    furthest_stage,
    outcome,
    arr,
    channel,
    is_marketing_sourced,
    is_new_logo,
    created_at,
    closed_at
from {{ source('raw', 'opportunities') }}
