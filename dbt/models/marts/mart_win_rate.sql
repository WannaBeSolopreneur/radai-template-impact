with bounds as (
    select
        cast(quarter.win_rate_start as timestamp) as win_rate_start,
        cast(meta.as_of as timestamp) as as_of
    from {{ ref('stg_quarter') }} as quarter
    cross join {{ ref('stg_generation_meta') }} as meta
)

select
    cast(bounds.as_of as date) as as_of,
    opportunities.segment,
    case opportunities.segment
        when 'radiology_group' then 'Radiology group'
        else 'Health system'
    end as segment_label,
    count(*) as closed_deals,
    sum(case when opportunities.outcome = 'won' then 1 else 0 end) as won_deals,
    sum(case when opportunities.outcome = 'won' then 1 else 0 end) * 1.0 / count(*) as win_rate
from {{ ref('fct_opportunities') }} as opportunities
cross join bounds
where opportunities.outcome in ('won', 'lost')
    and opportunities.closed_at >= bounds.win_rate_start
    and opportunities.closed_at < bounds.as_of
group by 1, 2, 3
