select week_start
from {{ ref('mart_weekly_turnaround') }}
where dayofweek(week_start) <> 1

union all

select 'weekend_not_quieter'
from (
    select
        sum(case when dow_index >= 5 then n_studies else 0 end) / 2.0 as weekend_daily,
        sum(case when dow_index < 5 then n_studies else 0 end) / 5.0 as weekday_daily
    from {{ ref('mart_heatmap') }}
    where modality = 'All'
) as days
where weekend_daily >= weekday_daily

union all

select 'night_not_quieter'
from (
    select
        sum(case when exam_hour = 2 then n_studies else 0 end) as night_n,
        sum(case when exam_hour = 10 then n_studies else 0 end) as day_n
    from {{ ref('mart_heatmap') }}
    where modality = 'All'
) as hours
where night_n * 3 >= day_n

union all

select 'monday_not_slower'
from {{ ref('mart_heatmap') }} as monday
inner join {{ ref('mart_heatmap') }} as wednesday
    on monday.modality = 'All'
    and wednesday.modality = 'All'
    and monday.exam_hour = 10
    and wednesday.exam_hour = 10
    and monday.dow_index = 0
    and wednesday.dow_index = 2
where monday.median_turnaround_minutes <= wednesday.median_turnaround_minutes
    or monday.too_few_studies <> 0
    or wednesday.too_few_studies <> 0

union all

select modality
from {{ ref('mart_modality_box') }}
where p90 < p50 * 1.4
    or p10 > p25
    or p25 > p50
    or p50 > p75
    or p75 > p90

union all

select 'ai_counts'
where (
    select sum(n_studies)
    from {{ ref('mart_ai_specialty') }}
    where modality = 'All'
) <> (
    select sum(is_ai_scored)
    from {{ ref('fct_studies_metric') }}
    where period = 'after'
)

union all

select 'period_vs_launch'
from {{ ref('fct_studies') }}
where (period = 'after' and exam_completed_at < launch_at)
    or (period = 'before' and exam_completed_at >= launch_at)
