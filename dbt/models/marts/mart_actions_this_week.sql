with horizon as (
    select renewal_horizon_days
    from {{ ref('stg_quarter') }}
),

renewals as (
    select
        count(*) as n_accounts,
        array_to_string(list(account_name order by account_name), ' and ') as names
    from {{ ref('mart_account_health') }}
    cross join horizon
    where renewal_at_risk = 1
),

channels as (
    select
        channel_name,
        cost_per_opportunity
    from {{ ref('mart_channel_performance') }}
    where opportunities > 0
    order by cost_per_opportunity, sort_order
    limit 1
),

wins as (
    select
        max(case when segment = 'health_system' then win_rate end) as health_system_rate,
        max(case when segment = 'radiology_group' then win_rate end) as radiology_rate
    from {{ ref('mart_win_rate') }}
),

goals as (
    select
        max(case when goal_id = 'bookings' then status end) as bookings_status,
        max(case when goal_id = 'bookings' then current_label end) as bookings_current,
        max(case when goal_id = 'bookings' then target_label end) as bookings_target,
        max(case when goal_id = 'ai_adoption' then status end) as adoption_status,
        max(case when goal_id = 'ai_adoption' then current_label end) as adoption_current,
        max(case when goal_id = 'ai_adoption' then target_label end) as adoption_target,
        max(case when goal_id = 'minutes_saved' then status end) as minutes_status,
        max(case when goal_id = 'minutes_saved' then current_label end) as minutes_current,
        max(case when goal_id = 'minutes_saved' then target_label end) as minutes_target,
        max(case when goal_id = 'pipeline_coverage' then status end) as coverage_status,
        max(case when goal_id = 'pipeline_coverage' then current_label end) as coverage_current,
        max(case when goal_id = 'pipeline_coverage' then target_label end) as coverage_target
    from {{ ref('mart_goal_status') }}
),

drafts as (
    select
        'renewal_risk' as action_id,
        1 as sort_order,
        'customers' as section_id,
        'Renewals' as title,
        case
            when renewals.n_accounts = 1
                then renewals.names
                    || ' renews within '
                    || cast(horizon.renewal_horizon_days as varchar)
                    || ' days and AI usage is falling. Book a check-in.'
            when renewals.n_accounts = 2
                then renewals.names
                    || ' renew within '
                    || cast(horizon.renewal_horizon_days as varchar)
                    || ' days and AI usage is falling. Book a check-in.'
            else cast(renewals.n_accounts as varchar)
                || ' accounts renew within '
                || cast(horizon.renewal_horizon_days as varchar)
                || ' days and AI usage is falling. Book a check-in.'
        end as sentence
    from renewals
    cross join horizon
    where renewals.n_accounts > 0

    union all

    select
        'bookings_pace' as action_id,
        2 as sort_order,
        'sales-bookings' as section_id,
        'Bookings' as title,
        'New bookings are at '
            || goals.bookings_current
            || ' against a '
            || goals.bookings_target
            || ' quarter goal, and the pace is behind. Review deals in contract.'
            as sentence
    from goals
    where goals.bookings_status = 'behind'

    union all

    select
        'win_rate' as action_id,
        3 as sort_order,
        'sales-win' as section_id,
        'Win rate' as title,
        'Health systems win '
            || cast(cast(round(wins.health_system_rate * 100, 0) as integer) as varchar)
            || '% of closed deals. Radiology groups win '
            || cast(cast(round(wins.radiology_rate * 100, 0) as integer) as varchar)
            || '%. Adjust the playbook.'
            as sentence
    from wins
    where wins.health_system_rate + 0.10 < wins.radiology_rate

    union all

    select
        'channel_cost' as action_id,
        4 as sort_order,
        'marketing' as section_id,
        'Marketing' as title,
        channels.channel_name
            || ' bring pipeline at the lowest cost, '
            || '$'
            || cast(cast(floor(channels.cost_per_opportunity / 1000) as integer) as varchar)
            || ','
            || lpad(cast(cast(round(channels.cost_per_opportunity, 0) as integer) % 1000 as varchar), 3, '0')
            || ' per opportunity. Add one more this quarter.'
            as sentence
    from channels
    where channels.cost_per_opportunity >= 1000

    union all

    select
        'adoption' as action_id,
        6 as sort_order,
        'customers' as section_id,
        'Adoption' as title,
        'AI adoption is '
            || goals.adoption_current
            || ' against a '
            || goals.adoption_target
            || ' goal. Start with the accounts whose usage is falling.'
            as sentence
    from goals
    where goals.adoption_status in ('behind', 'at_risk')

    union all

    select
        'minutes_saved' as action_id,
        5 as sort_order,
        'time-saved' as section_id,
        'Time saved' as title,
        'Radiologists saved about '
            || goals.minutes_current
            || ' each over the last 30 days, ahead of the '
            || goals.minutes_target
            || ' goal. Use that story on the next renewal.'
            as sentence
    from goals
    where goals.minutes_status = 'on_track'
),

ranked as (
    select
        action_id,
        sort_order,
        section_id,
        title,
        sentence,
        row_number() over (order by sort_order) as action_rank
    from drafts
)

select
    action_id,
    action_rank as sort_order,
    section_id,
    title,
    sentence
from ranked
where action_rank <= 5
