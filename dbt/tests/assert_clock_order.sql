select study_id
from {{ ref('int_studies') }}
where report_signed_at < report_started_at
    or report_started_at < exam_completed_at
    or turnaround_minutes <= 0
    or time_on_report_minutes <= 0

union all

select study_id
from {{ ref('fct_studies') }}
where report_signed_at < report_started_at
    or report_started_at < exam_completed_at

union all

select study_id
from {{ ref('fct_studies_metric') }}
where words_dictated < 20
    or turnaround_minutes < time_on_report_minutes
