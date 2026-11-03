-- Customer-facing study grain. Other customers and test fixtures never land here.
select
    study_id,
    customer_id,
    customer_name,
    site_id,
    site_name,
    size_band,
    radiologist_id,
    modality,
    specialty,
    priority,
    exam_completed_at,
    report_started_at,
    report_signed_at,
    template_id,
    template_version,
    used_template,
    words_dictated,
    ai_impression_status,
    is_test_fixture,
    is_ai_accepted,
    is_ai_scored,
    turnaround_minutes,
    time_on_report_minutes,
    week_start,
    exam_hour,
    dow_index,
    period,
    is_partial_period,
    launch_at
from {{ ref('int_studies') }}
where customer_id = '{{ var("customer_id") }}'
    and is_test_fixture = 0
