select 'raw_not_slower'
from {{ ref('mart_headline') }}
where raw_change_minutes <= 5

union all

select 'adjusted_not_faster'
from {{ ref('mart_headline') }}
where adjusted_change_minutes >= -0.5

union all

select 'report_not_faster'
from {{ ref('mart_headline') }}
where adjusted_report_change_minutes >= -1

union all

select 'mri_shift'
from {{ ref('mart_headline') }}
where mri_share_after - mri_share_before <= 0.10

union all

select 'usage'
from {{ ref('mart_headline') }}
where template_usage_after <= template_usage_before

union all

select 'ai'
from {{ ref('mart_headline') }}
where ai_acceptance_after <= ai_acceptance_before

union all

select before_period.modality
from {{ ref('mart_modality_period') }} as before_period
inner join {{ ref('mart_modality_period') }} as after_period
    on before_period.modality = after_period.modality
    and before_period.period = 'before'
    and after_period.period = 'after'
where before_period.modality <> 'All'
    and (
        after_period.median_time_on_report_minutes
            >= before_period.median_time_on_report_minutes - 0.4
        or after_period.median_turnaround_minutes
            >= before_period.median_turnaround_minutes
    )
