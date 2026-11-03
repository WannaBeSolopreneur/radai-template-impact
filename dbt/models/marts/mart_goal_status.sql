with calendar as (
    select
        quarter.quarter_start,
        quarter.quarter_end,
        quarter.on_track_ratio,
        quarter.at_risk_ratio,
        cast(meta.as_of as date) as as_of,
        {{ datediff_days('quarter.quarter_start', 'cast(meta.as_of as date)') }} as days_elapsed,
        {{ datediff_days('quarter.quarter_start', 'quarter.quarter_end') }} + 1 as days_in_quarter
    from {{ ref('stg_quarter') }} as quarter
    cross join {{ ref('stg_generation_meta') }} as meta
),

bookings as (
    select
        coalesce(sum(q4_won_arr), 0) as bookings_arr,
        coalesce(sum(q4_new_logo), 0) as new_logos
    from {{ ref('fct_opportunities') }}
),

open_pipeline as (
    select coalesce(sum(arr), 0) as open_arr
    from {{ ref('fct_opportunities') }}
    where outcome = 'open'
        and furthest_rank >= 2
),

marketing as (
    select coalesce(sum(q4_marketing_arr), 0) as marketing_arr
    from {{ ref('fct_opportunities') }}
),

retention as (
    select sum(arr) * 1.0 / sum(arr_one_year_ago) as nrr
    from {{ ref('stg_accounts') }}
    where arr_one_year_ago > 0
),

usage as (
    select
        sum(ai_used) * 1.0 / count(*) as adoption,
        sum(case when account_id = '{{ var("customer_id") }}' then 1 else 0 end) as nb_studies,
        count(
            distinct case
                when account_id = '{{ var("customer_id") }}' then radiologist_id
            end
        ) as nb_radiologists
    from {{ ref('fct_portfolio_studies') }}
),

saved as (
    select -adjusted_report_change_minutes as minutes_per_report
    from {{ ref('mart_case_mix_change') }}
),

actuals as (
    select
        'bookings' as goal_id,
        bookings.bookings_arr as current_value
    from bookings

    union all

    select
        'new_logos' as goal_id,
        bookings.new_logos as current_value
    from bookings

    union all

    select
        'pipeline_coverage' as goal_id,
        open_pipeline.open_arr * 1.0 / nullif(
            (select target_value from {{ ref('stg_goals') }} where goal_id = 'bookings')
            - bookings.bookings_arr,
            0
        ) as current_value
    from open_pipeline
    cross join bookings

    union all

    select
        'net_revenue_retention' as goal_id,
        retention.nrr as current_value
    from retention

    union all

    select
        'marketing_pipeline' as goal_id,
        marketing.marketing_arr as current_value
    from marketing

    union all

    select
        'ai_adoption' as goal_id,
        usage.adoption as current_value
    from usage

    union all

    select
        'minutes_saved' as goal_id,
        saved.minutes_per_report * usage.nb_studies / nullif(usage.nb_radiologists, 0) as current_value
    from saved
    cross join usage
),

scored as (
    select
        goals.goal_id,
        goals.label,
        goals.detail,
        goals.unit,
        goals.metric_kind,
        actuals.current_value,
        goals.target_value,
        goals.sort_order,
        calendar.as_of,
        calendar.days_elapsed,
        calendar.days_in_quarter,
        calendar.on_track_ratio,
        calendar.at_risk_ratio,
        actuals.current_value / nullif(goals.target_value, 0) as progress_ratio,
        case
            when goals.metric_kind = 'pace'
                then calendar.days_elapsed * 1.0 / calendar.days_in_quarter
        end as pace_ratio,
        case
            when goals.metric_kind = 'pace'
                and actuals.current_value
                    >= goals.target_value
                    * calendar.days_elapsed * 1.0 / calendar.days_in_quarter
                    * calendar.on_track_ratio
                then 'on_track'
            when goals.metric_kind = 'pace'
                and actuals.current_value
                    >= goals.target_value
                    * calendar.days_elapsed * 1.0 / calendar.days_in_quarter
                    * calendar.at_risk_ratio
                then 'at_risk'
            when goals.metric_kind = 'pace' then 'behind'
            when actuals.current_value >= goals.target_value * calendar.on_track_ratio
                then 'on_track'
            when actuals.current_value >= goals.target_value * calendar.at_risk_ratio
                then 'at_risk'
            else 'behind'
        end as status
    from {{ ref('stg_goals') }} as goals
    inner join actuals
        on goals.goal_id = actuals.goal_id
    cross join calendar
),

labeled as (
    select
        goal_id,
        label,
        detail,
        unit,
        metric_kind,
        current_value,
        target_value,
        sort_order,
        as_of,
        days_elapsed,
        days_in_quarter,
        on_track_ratio,
        at_risk_ratio,
        progress_ratio,
        pace_ratio,
        status,
        case status
            when 'on_track' then 'On track'
            when 'at_risk' then 'At risk'
            else 'Behind'
        end as status_label,
        case unit
            when 'currency' then
                case
                    when abs(current_value) >= 1000000
                        then '$' || rtrim(rtrim(cast(cast(round(abs(current_value) / 1000000, 2) as decimal(10, 2)) as varchar), '0'), '.') || 'M'
                    else '$' || cast(cast(round(abs(current_value) / 1000, 0) as integer) as varchar) || 'k'
                end
            when 'count' then cast(cast(round(current_value, 0) as integer) as varchar)
            when 'multiple' then {{ multiple_label('current_value') }}
            when 'percent' then
                rtrim(rtrim(cast(cast(round(current_value * 100, 1) as decimal(10, 1)) as varchar), '0'), '.') || '%'
            else cast(cast(round(current_value, 0) as integer) as varchar) || ' min'
        end as current_label,
        case unit
            when 'currency' then
                case
                    when abs(target_value) >= 1000000
                        then '$' || rtrim(rtrim(cast(cast(round(abs(target_value) / 1000000, 2) as decimal(10, 2)) as varchar), '0'), '.') || 'M'
                    else '$' || cast(cast(round(abs(target_value) / 1000, 0) as integer) as varchar) || 'k'
                end
            when 'count' then cast(cast(round(target_value, 0) as integer) as varchar)
            when 'multiple' then {{ multiple_label('target_value') }}
            when 'percent' then
                rtrim(rtrim(cast(cast(round(target_value * 100, 1) as decimal(10, 1)) as varchar), '0'), '.') || '%'
            else cast(cast(round(target_value, 0) as integer) as varchar) || ' min'
        end as target_label
    from scored
)

select
    goal_id,
    label,
    detail,
    unit,
    metric_kind,
    current_value,
    target_value,
    current_label,
    target_label,
    sort_order,
    as_of,
    days_elapsed,
    days_in_quarter,
    on_track_ratio,
    at_risk_ratio,
    progress_ratio,
    pace_ratio,
    status,
    status_label
from labeled
