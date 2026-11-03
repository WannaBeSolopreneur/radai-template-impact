-- Goal values, pace rules, funnel shape, channels, win rates, and this week's actions.

select 'bookings' as check_name
from {{ ref('mart_goal_status') }}
where goal_id = 'bookings'
    and (
        abs(current_value - 540000) > 0.1
        or abs(target_value - 2400000) > 0.1
        or status <> 'behind'
        or current_label <> '$540k'
        or target_label <> '$2.4M'
    )

union all

select 'new_logos'
from {{ ref('mart_goal_status') }}
where goal_id = 'new_logos'
    and (
        abs(current_value - 3) > 0.1
        or status <> 'on_track'
    )

union all

select 'pipeline_coverage'
from {{ ref('mart_goal_status') }}
where goal_id = 'pipeline_coverage'
    and (
        abs(current_value - (3940000.0 / 1860000.0)) > 0.001
        or status <> 'behind'
    )

union all

select 'net_revenue_retention'
from {{ ref('mart_goal_status') }}
where goal_id = 'net_revenue_retention'
    and (
        abs(current_value - (7160000.0 / 6900000.0)) > 0.0001
        or status <> 'at_risk'
    )

union all

select 'marketing_pipeline'
from {{ ref('mart_goal_status') }}
where goal_id = 'marketing_pipeline'
    and (
        abs(current_value - 1520000) > 0.1
        or status <> 'on_track'
        or current_label <> '$1.52M'
    )

union all

select 'calendar'
from {{ ref('mart_goal_status') }}
where days_elapsed <> 33
    or days_in_quarter <> 92

union all

select goal_id
from {{ ref('mart_goal_status') }}
where metric_kind = 'pace'
    and (
        (
            status = 'on_track'
            and current_value + 0.001
                < target_value * days_elapsed * 1.0 / days_in_quarter * on_track_ratio
        )
        or (
            status = 'at_risk'
            and (
                current_value + 0.001
                    < target_value * days_elapsed * 1.0 / days_in_quarter * at_risk_ratio
                or current_value
                    >= target_value * days_elapsed * 1.0 / days_in_quarter * on_track_ratio
            )
        )
        or (
            status = 'behind'
            and current_value
                >= target_value * days_elapsed * 1.0 / days_in_quarter * at_risk_ratio
        )
        or status not in ('on_track', 'at_risk', 'behind')
    )

union all

select goal_id
from {{ ref('mart_goal_status') }}
where metric_kind = 'snapshot'
    and (
        (
            status = 'on_track'
            and current_value + 0.0000001 < target_value * on_track_ratio
        )
        or (
            status = 'at_risk'
            and (
                current_value + 0.0000001 < target_value * at_risk_ratio
                or current_value >= target_value * on_track_ratio
            )
        )
        or (
            status = 'behind'
            and current_value >= target_value * at_risk_ratio
        )
    )

union all

select 'adoption_formula'
from {{ ref('mart_goal_status') }} as goals
cross join (
    select sum(ai_used) * 1.0 / count(*) as adoption
    from {{ ref('fct_portfolio_studies') }}
) as usage
where goals.goal_id = 'ai_adoption'
    and abs(goals.current_value - usage.adoption) > 0.0001

union all

select 'minutes_formula'
from {{ ref('mart_goal_status') }} as goals
cross join (
    select
        -change.adjusted_report_change_minutes
            * count(*)
            / count(distinct studies.radiologist_id) as minutes_saved
    from {{ ref('fct_portfolio_studies') }} as studies
    cross join {{ ref('mart_case_mix_change') }} as change
    where studies.account_id = '{{ var("customer_id") }}'
    group by change.adjusted_report_change_minutes
) as saved
where goals.goal_id = 'minutes_saved'
    and abs(goals.current_value - saved.minutes_saved) > 0.05

union all

select 'october_bookings'
from {{ ref('mart_monthly_bookings') }}
where month_start = date '2026-10-01'
    and abs(bookings_arr - 540000) > 0.1

union all

select 'funnel_not_monotonic'
from {{ ref('mart_funnel') }} as earlier
inner join {{ ref('mart_funnel') }} as later
    on later.stage_rank = earlier.stage_rank + 1
where later.reached > earlier.reached

union all

select 'funnel_won'
where (
    select reached
    from {{ ref('mart_funnel') }}
    where stage = 'won'
) <> (
    select count(*)
    from {{ ref('fct_opportunities') }} as opportunities
    cross join {{ ref('stg_quarter') }} as quarter
    cross join {{ ref('stg_generation_meta') }} as meta
    where opportunities.furthest_rank = 6
        and opportunities.created_at >= cast(quarter.funnel_start as timestamp)
        and opportunities.created_at < cast(meta.as_of as timestamp)
)

union all

select 'webinars'
from {{ ref('mart_channel_performance') }}
where channel = 'webinars'
    and (
        opportunities <> 12
        or abs(pipeline_arr - 640000) > 0.1
        or abs(cost_per_opportunity - 1250) > 0.01
    )

union all

select 'cheapest_channel'
where (
    select channel
    from {{ ref('mart_channel_performance') }}
    order by cost_per_opportunity, sort_order
    limit 1
) <> 'webinars'

union all

select 'radiology_win'
from {{ ref('mart_win_rate') }}
where segment = 'radiology_group'
    and (won_deals <> 12 or closed_deals <> 16)

union all

select 'health_system_win'
from {{ ref('mart_win_rate') }}
where segment = 'health_system'
    and (won_deals <> 3 or closed_deals <> 12)

union all

select 'renewal_pair'
where (
    select count(*)
    from {{ ref('mart_account_health') }}
    where renewal_at_risk = 1
        and account_id in ('acct_lakeside', 'acct_summit')
        and trend = 'down'
) <> 2

union all

select account_id
from {{ ref('mart_account_health') }}
where renewal_at_risk = 1
    and account_id not in ('acct_lakeside', 'acct_summit')

union all

select 'delta_trend'
from {{ ref('mart_account_health') }}
where account_id = 'acct_delta'
    and trend <> 'up'

union all

select 'action_count'
where (
    select count(*)
    from {{ ref('mart_actions_this_week') }}
) not between 3 and 5

union all

select action_id
from {{ ref('mart_actions_this_week') }}
where position(';' in sentence) > 0
    or position('—' in sentence) > 0
    or sentence is null
    or section_id is null

union all

select 'renewal_action'
where (
    select count(*)
    from {{ ref('mart_actions_this_week') }}
    where action_id = 'renewal_risk'
        and sentence like '%Lakeside Imaging Group%'
        and sentence like '%Summit Health System%'
        and section_id = 'customers'
) <> 1

union all

select 'channel_action'
where (
    select count(*)
    from {{ ref('mart_actions_this_week') }}
    where action_id = 'channel_cost'
        and sentence like '%Webinars%'
        and sentence like '%$1,250%'
) <> 1

union all

select 'win_action'
where (
    select count(*)
    from {{ ref('mart_actions_this_week') }}
    where action_id = 'win_rate'
        and sentence like '%25%'
        and sentence like '%75%'
) <> 1
