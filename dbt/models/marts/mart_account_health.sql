with bounds as (
    select
        cast(meta.as_of as date) as as_of,
        meta.partial_start,
        quarter.renewal_horizon_days,
        quarter.trend_points,
        {{ date_add_days('cast(meta.as_of as date)', -30) }} as recent_start,
        {{ date_add_days('cast(meta.as_of as date)', -60) }} as prior_start
    from {{ ref('stg_generation_meta') }} as meta
    cross join {{ ref('stg_quarter') }} as quarter
),

usage as (
    select
        studies.customer_id as account_id,
        count(
            case
                when studies.exam_completed_at >= cast(bounds.recent_start as timestamp)
                    and studies.exam_completed_at < bounds.partial_start
                    then 1
            end
        ) as recent_studies,
        count(
            case
                when studies.exam_completed_at >= cast(bounds.recent_start as timestamp)
                    and studies.exam_completed_at < bounds.partial_start
                    and studies.ai_impression_status in ('accepted', 'edited')
                    then 1
            end
        ) as recent_ai,
        count(
            case
                when studies.exam_completed_at >= cast(bounds.prior_start as timestamp)
                    and studies.exam_completed_at < cast(bounds.recent_start as timestamp)
                    then 1
            end
        ) as prior_studies,
        count(
            case
                when studies.exam_completed_at >= cast(bounds.prior_start as timestamp)
                    and studies.exam_completed_at < cast(bounds.recent_start as timestamp)
                    and studies.ai_impression_status in ('accepted', 'edited')
                    then 1
            end
        ) as prior_ai
    from {{ ref('int_studies') }} as studies
    cross join bounds
    where studies.is_test_fixture = 0
    group by 1
),

scored as (
    select
        accounts.account_id,
        accounts.account_name,
        accounts.segment,
        case accounts.segment
            when 'radiology_group' then 'Radiology group'
            else 'Health system'
        end as segment_label,
        accounts.arr,
        accounts.renewal_date,
        {{ datediff_days('bounds.as_of', 'accounts.renewal_date') }} as days_to_renewal,
        bounds.renewal_horizon_days,
        bounds.as_of,
        coalesce(usage.recent_studies, 0) as recent_studies,
        case
            when coalesce(usage.recent_studies, 0) = 0 then null
            else usage.recent_ai * 1.0 / usage.recent_studies
        end as recent_ai_rate,
        case
            when coalesce(usage.prior_studies, 0) < 30 then 'new'
            when coalesce(usage.recent_studies, 0) = 0 then 'down'
            when usage.recent_ai * 1.0 / usage.recent_studies
                - usage.prior_ai * 1.0 / usage.prior_studies
                <= -bounds.trend_points
                then 'down'
            when usage.recent_ai * 1.0 / usage.recent_studies
                - usage.prior_ai * 1.0 / usage.prior_studies
                >= bounds.trend_points
                then 'up'
            else 'flat'
        end as trend
    from {{ ref('stg_accounts') }} as accounts
    cross join bounds
    left join usage
        on accounts.account_id = usage.account_id
    where accounts.is_active = 1
),

banded as (
    select
        account_id,
        account_name,
        segment,
        segment_label,
        arr,
        renewal_date,
        days_to_renewal,
        renewal_horizon_days,
        as_of,
        recent_studies,
        recent_ai_rate,
        trend,
        cast(round(
            100 * coalesce(recent_ai_rate, 0) * 0.75
            + case trend
                when 'up' then 25
                when 'flat' then 18
                when 'new' then 18
                else 8
            end
        ) as integer) as health_score
    from scored
)

select
    account_id,
    account_name,
    segment,
    segment_label,
    arr,
    renewal_date,
    case
        when extract(year from renewal_date) = extract(year from as_of)
            then {{ month_abbr('renewal_date') }}
                || ' '
                || cast(extract(day from renewal_date) as integer)
        else {{ month_abbr('renewal_date') }}
            || ' '
            || cast(extract(day from renewal_date) as integer)
            || ', '
            || cast(extract(year from renewal_date) as integer)
    end as renewal_label,
    days_to_renewal,
    recent_studies,
    recent_ai_rate,
    case
        when recent_ai_rate is null then 'No studies'
        else rtrim(rtrim(cast(cast(round(recent_ai_rate * 100, 1) as decimal(10, 1)) as varchar), '0'), '.') || '%'
    end as adoption_label,
    trend,
    case trend
        when 'up' then 'Up'
        when 'down' then 'Down'
        when 'flat' then 'Flat'
        else 'New'
    end as trend_label,
    health_score,
    case
        when health_score >= 75 then 'healthy'
        when health_score >= 55 then 'watch'
        else 'risk'
    end as health_band,
    case
        when health_score >= 75 then 'Healthy'
        when health_score >= 55 then 'Watch'
        else 'At risk'
    end as health_label,
    case
        when trend = 'down' and days_to_renewal between 0 and renewal_horizon_days then 1
        else 0
    end as renewal_at_risk,
    row_number() over (
        order by
            case
                when trend = 'down' and days_to_renewal between 0 and renewal_horizon_days then 0
                else 1
            end,
            days_to_renewal,
            account_name
    ) as display_order
from banded
