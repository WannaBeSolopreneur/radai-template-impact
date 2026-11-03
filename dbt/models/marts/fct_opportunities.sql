with bounds as (
    select
        cast(quarter.quarter_start as timestamp) as quarter_start,
        cast(meta.as_of as timestamp) as as_of
    from {{ ref('stg_quarter') }} as quarter
    cross join {{ ref('stg_generation_meta') }} as meta
)

select
    opportunities.opportunity_id,
    opportunities.account_id,
    opportunities.prospect_name,
    opportunities.segment,
    opportunities.stage,
    opportunities.furthest_stage,
    opportunities.furthest_rank,
    opportunities.outcome,
    opportunities.arr,
    opportunities.channel,
    opportunities.is_marketing_sourced,
    opportunities.is_new_logo,
    opportunities.created_at,
    opportunities.closed_at,
    case
        when opportunities.outcome = 'won'
            and opportunities.closed_at >= bounds.quarter_start
            and opportunities.closed_at < bounds.as_of
            then opportunities.arr
        else 0
    end as q4_won_arr,
    case
        when opportunities.outcome = 'won'
            and opportunities.is_new_logo = 1
            and opportunities.closed_at >= bounds.quarter_start
            and opportunities.closed_at < bounds.as_of
            then 1
        else 0
    end as q4_new_logo,
    case
        when opportunities.is_marketing_sourced = 1
            and opportunities.furthest_rank >= 2
            and opportunities.created_at >= bounds.quarter_start
            and opportunities.created_at < bounds.as_of
            then opportunities.arr
        else 0
    end as q4_marketing_arr
from {{ ref('int_opportunities') }} as opportunities
cross join bounds
