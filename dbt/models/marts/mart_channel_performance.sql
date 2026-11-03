with bounds as (
    select
        cast(quarter.quarter_start as timestamp) as quarter_start,
        cast(meta.as_of as timestamp) as as_of
    from {{ ref('stg_quarter') }} as quarter
    cross join {{ ref('stg_generation_meta') }} as meta
)

select
    cast(bounds.as_of as date) as as_of,
    spend.channel,
    spend.channel_name,
    spend.spend,
    spend.sort_order,
    count(opportunities.opportunity_id) as opportunities,
    coalesce(sum(opportunities.arr), 0) as pipeline_arr,
    spend.spend * 1.0 / nullif(count(opportunities.opportunity_id), 0) as cost_per_opportunity
from {{ ref('stg_marketing_spend') }} as spend
cross join bounds
left join {{ ref('fct_opportunities') }} as opportunities
    on opportunities.channel = spend.channel
    and opportunities.created_at >= bounds.quarter_start
    and opportunities.created_at < bounds.as_of
    and opportunities.furthest_rank >= 2
group by
    bounds.as_of,
    spend.channel,
    spend.channel_name,
    spend.spend,
    spend.sort_order
