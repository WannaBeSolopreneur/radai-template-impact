with months as (
    select 0 as n
    union all select 1
    union all select 2
    union all select 3
    union all select 4
    union all select 5
    union all select 6
),

calendar as (
    select
        quarter.chart_start,
        cast(date_trunc('month', meta.as_of) as date) as current_month,
        cast(meta.as_of as date) as as_of,
        (
            select target_value
            from {{ ref('stg_goals') }}
            where goal_id = 'bookings'
        ) / 3.0 as monthly_goal
    from {{ ref('stg_quarter') }} as quarter
    cross join {{ ref('stg_generation_meta') }} as meta
),

spine as (
    select
        cast({{ add_months('calendar.chart_start', 'months.n') }} as date) as month_start,
        calendar.current_month,
        calendar.as_of,
        calendar.monthly_goal
    from months
    cross join calendar
),

wins as (
    select
        cast(date_trunc('month', closed_at) as date) as month_start,
        sum(arr) as bookings_arr
    from {{ ref('fct_opportunities') }}
    where outcome = 'won'
    group by 1
)

select
    spine.month_start,
    {{ month_abbr('spine.month_start') }} as month_label,
    coalesce(wins.bookings_arr, 0) as bookings_arr,
    spine.monthly_goal,
    case
        when spine.month_start = spine.current_month
            and {{ datediff_days('spine.month_start', 'spine.as_of') }} <= 7
            and coalesce(wins.bookings_arr, 0) = 0
            then {{ month_full('spine.month_start') }} || ' has just started.'
    end as month_note
from spine
left join wins
    on spine.month_start = wins.month_start
where spine.month_start <= spine.current_month
