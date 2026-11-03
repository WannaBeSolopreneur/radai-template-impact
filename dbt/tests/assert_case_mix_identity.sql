with calc as (
    select
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
        on weights.modality = periods.modality
    where periods.period in ('before', 'after')
)

select 'weights'
from {{ ref('mart_case_mix_weights') }}
having abs(sum(weight) - 1) > 0.0001
    or count(*) <> 4

union all

select 'identity'
from {{ ref('mart_case_mix_change') }} as change
cross join calc
where abs(change.adjusted_before_minutes - calc.adjusted_before_minutes) > 0.05
    or abs(change.adjusted_after_minutes - calc.adjusted_after_minutes) > 0.05
    or abs(change.adjusted_report_before_minutes - calc.adjusted_report_before_minutes) > 0.05
    or abs(change.adjusted_report_after_minutes - calc.adjusted_report_after_minutes) > 0.05
    or abs(change.adjusted_change_minutes - (change.adjusted_after_minutes - change.adjusted_before_minutes)) > 0.001
    or abs(change.raw_change_minutes - (change.raw_after_minutes - change.raw_before_minutes)) > 0.001
