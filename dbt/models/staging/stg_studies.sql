with source as (
    select
        study_id,
        customer_id,
        site_id,
        radiologist_id,
        modality,
        specialty,
        priority,
        cast(exam_completed_at as timestamp) as exam_completed_at,
        cast(report_started_at as timestamp) as report_started_at,
        cast(report_signed_at as timestamp) as report_signed_at,
        template_id,
        template_version,
        cast(used_template as integer) as used_template,
        cast(words_dictated as integer) as words_dictated,
        ai_impression_status,
        cast(is_test_fixture as integer) as is_test_fixture,
        cast(ingested_at as timestamp) as ingested_at,
        cast(source_row as integer) as source_row
    from {{ source('raw', 'studies') }}
),

ranked as (
    select
        source.*,
        count(*) over (partition by study_id) as raw_copy_count,
        row_number() over (
            partition by study_id
            order by ingested_at desc, source_row desc
        ) as copy_rank
    from source
),

deduped as (
    select *
    from ranked
    where copy_rank = 1
),

filled as (
    select
        deduped.study_id,
        deduped.customer_id,
        deduped.site_id,
        deduped.radiologist_id,
        coalesce(deduped.modality, catalog.modality) as modality,
        coalesce(deduped.specialty, catalog.specialty) as specialty,
        deduped.priority,
        deduped.exam_completed_at,
        deduped.report_started_at,
        deduped.report_signed_at,
        deduped.template_id,
        deduped.template_version,
        deduped.used_template,
        deduped.words_dictated,
        deduped.ai_impression_status,
        deduped.is_test_fixture,
        deduped.ingested_at,
        deduped.source_row,
        deduped.raw_copy_count,
        case
            when deduped.modality is null and catalog.modality is not null then 1
            else 0
        end as modality_was_filled
    from deduped
    left join {{ ref('stg_template_catalog') }} as catalog
        on deduped.template_id = catalog.template_id
),

skewed as (
    select
        filled.*,
        {{ seconds_between('report_started_at', 'exam_completed_at') }} as clock_skew_seconds
    from filled
),

repaired as (
    select
        skewed.*,
        case
            when report_started_at < exam_completed_at
                and clock_skew_seconds <= 15 * 60
                then exam_completed_at
            else report_started_at
        end as report_started_at_clean,
        case
            when report_started_at < exam_completed_at
                and clock_skew_seconds <= 15 * 60
                then {{ add_seconds('report_signed_at', 'clock_skew_seconds') }}
            else report_signed_at
        end as report_signed_at_clean,
        case
            when report_started_at < exam_completed_at
                and clock_skew_seconds <= 15 * 60
                then 1
            else 0
        end as chronology_was_repaired
    from skewed
)

select
    study_id,
    customer_id,
    site_id,
    radiologist_id,
    modality,
    specialty,
    priority,
    exam_completed_at,
    report_started_at_clean as report_started_at,
    report_signed_at_clean as report_signed_at,
    template_id,
    template_version,
    used_template,
    words_dictated,
    ai_impression_status,
    is_test_fixture,
    ingested_at,
    source_row,
    raw_copy_count,
    modality_was_filled,
    chronology_was_repaired
from repaired
where report_signed_at_clean >= report_started_at_clean
    and report_started_at_clean >= exam_completed_at
