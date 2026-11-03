-- Within each modality, compare medians. Then weight by the pre-launch mix.
-- A negative change means faster. The raw change does not hold the mix still.
with weighted as (
    select
        weights.customer_id,
        sum(
            case
                when periods.period = 'before'
                    then weights.weight * periods.median_turnaround_minutes
            end
        ) as adjusted_before_minutes,
        sum(
            case
                when periods.period = 'after'
                    then weights.weight * periods.median_turnaround_minutes
            end
        ) as adjusted_after_minutes,
        sum(
            case
                when periods.period = 'before'
                    then weights.weight * periods.median_time_on_report_minutes
            end
        ) as adjusted_report_before_minutes,
        sum(
            case
                when periods.period = 'after'
                    then weights.weight * periods.median_time_on_report_minutes
            end
        ) as adjusted_report_after_minutes
    from {{ ref('mart_case_mix_weights') }} as weights
    inner join {{ ref('mart_modality_period') }} as periods
        on weights.customer_id = periods.customer_id
        and weights.modality = periods.modality
    where weights.customer_id = '{{ var("customer_id") }}'
        and periods.period in ('before', 'after')
    group by 1
),

raw_turnaround as (
    select
        customer_id,
        median(case when period = 'before' then turnaround_minutes end) as raw_before_minutes,
        median(case when period = 'after' then turnaround_minutes end) as raw_after_minutes
    from {{ ref('fct_studies_metric') }}
    where customer_id = '{{ var("customer_id") }}'
    group by 1
),

launch as (
    select launch_at
    from {{ ref('stg_generation_meta') }}
)

select
    weighted.customer_id,
    launch.launch_at,
    raw_turnaround.raw_before_minutes,
    raw_turnaround.raw_after_minutes,
    raw_turnaround.raw_after_minutes - raw_turnaround.raw_before_minutes as raw_change_minutes,
    weighted.adjusted_before_minutes,
    weighted.adjusted_after_minutes,
    weighted.adjusted_after_minutes - weighted.adjusted_before_minutes as adjusted_change_minutes,
    weighted.adjusted_report_before_minutes,
    weighted.adjusted_report_after_minutes,
    weighted.adjusted_report_after_minutes - weighted.adjusted_report_before_minutes as adjusted_report_change_minutes
from weighted
inner join raw_turnaround
    on weighted.customer_id = raw_turnaround.customer_id
cross join launch
