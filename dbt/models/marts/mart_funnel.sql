with stages as (
    select 'lead' as stage, 'Lead' as label, 1 as stage_rank
    union all select 'meeting', 'Meeting', 2
    union all select 'demo', 'Demo', 3
    union all select 'pilot', 'Pilot', 4
    union all select 'contract', 'Contract', 5
    union all select 'won', 'Won', 6
),

bounds as (
    select
        cast(quarter.funnel_start as timestamp) as funnel_start,
        cast(meta.as_of as timestamp) as as_of
    from {{ ref('stg_quarter') }} as quarter
    cross join {{ ref('stg_generation_meta') }} as meta
),

reached as (
    select
        stages.stage,
        stages.label,
        stages.stage_rank,
        count(opportunities.opportunity_id) as reached
    from stages
    left join {{ ref('fct_opportunities') }} as opportunities
        on opportunities.furthest_rank >= stages.stage_rank
        and opportunities.created_at >= (select funnel_start from bounds)
        and opportunities.created_at < (select as_of from bounds)
    group by 1, 2, 3
)

select
    stage,
    label,
    stage_rank,
    reached,
    reached * 1.0 / nullif(lag(reached) over (order by stage_rank), 0) as conversion_from_previous
from reached
