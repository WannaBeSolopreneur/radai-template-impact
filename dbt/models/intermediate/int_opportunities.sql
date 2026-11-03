select
    opportunity_id,
    account_id,
    prospect_name,
    segment,
    stage,
    furthest_stage,
    case furthest_stage
        when 'lead' then 1
        when 'meeting' then 2
        when 'demo' then 3
        when 'pilot' then 4
        when 'contract' then 5
        when 'won' then 6
    end as furthest_rank,
    outcome,
    arr,
    channel,
    is_marketing_sourced,
    is_new_logo,
    created_at,
    closed_at
from {{ ref('stg_opportunities') }}
