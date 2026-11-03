with meta as (
    select
        launch_at,
        partial_start
    from {{ ref('stg_generation_meta') }}
)

select
    studies.study_id,
    studies.customer_id,
    customers.customer_name,
    studies.site_id,
    sites.site_name,
    sites.size_band,
    studies.radiologist_id,
    studies.modality,
    studies.specialty,
    studies.priority,
    studies.exam_completed_at,
    studies.report_started_at,
    studies.report_signed_at,
    studies.template_id,
    studies.template_version,
    studies.used_template,
    studies.words_dictated,
    studies.ai_impression_status,
    studies.is_test_fixture,
    case
        when studies.ai_impression_status = 'accepted' then 1
        else 0
    end as is_ai_accepted,
    case
        when studies.ai_impression_status is not null then 1
        else 0
    end as is_ai_scored,
    {{ minutes_between('studies.exam_completed_at', 'studies.report_signed_at') }} as turnaround_minutes,
    {{ minutes_between('studies.report_started_at', 'studies.report_signed_at') }} as time_on_report_minutes,
    {{ week_start('studies.exam_completed_at') }} as week_start,
    cast(extract(hour from studies.exam_completed_at) as integer) as exam_hour,
    cast(((dayofweek(cast(studies.exam_completed_at as date)) + 6) % 7) as integer) as dow_index,
    case
        when studies.exam_completed_at >= meta.launch_at then 'after'
        else 'before'
    end as period,
    case
        when studies.exam_completed_at >= meta.partial_start then 1
        else 0
    end as is_partial_period,
    meta.launch_at
from {{ ref('stg_studies') }} as studies
inner join {{ ref('stg_customers') }} as customers
    on studies.customer_id = customers.customer_id
inner join {{ ref('stg_sites') }} as sites
    on studies.site_id = sites.site_id
inner join {{ ref('stg_radiologists') }} as radiologists
    on studies.radiologist_id = radiologists.radiologist_id
cross join meta
