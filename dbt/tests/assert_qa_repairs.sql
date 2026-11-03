-- Hand-built raw rows. A select returns a row only when the clean spine is wrong.

select 'qa_chrono_start'
from {{ ref('int_studies') }}
where study_id = 'qa_chrono'
    and report_started_at <> timestamp '2026-06-01 10:00:00'

union all

select 'qa_chrono_signed'
from {{ ref('int_studies') }}
where study_id = 'qa_chrono'
    and report_signed_at <> timestamp '2026-06-01 10:22:00'

union all

select 'qa_chrono_missing'
where (
    select count(*)
    from {{ ref('int_studies') }}
    where study_id = 'qa_chrono'
) <> 1

union all

select 'qa_duplicate_count'
where (
    select count(*)
    from {{ ref('int_studies') }}
    where study_id = 'qa_duplicate'
) <> 1

union all

select 'qa_duplicate_values'
from {{ ref('int_studies') }}
where study_id = 'qa_duplicate'
    and (modality <> 'CT' or words_dictated <> 160)

union all

select 'qa_modality'
from {{ ref('int_studies') }}
where study_id = 'qa_modality'
    and modality <> 'MRI'

union all

select 'qa_modality_missing'
where (
    select count(*)
    from {{ ref('int_studies') }}
    where study_id = 'qa_modality' and modality = 'MRI'
) <> 1

union all

select 'qa_exclude_missing'
where (
    select count(*)
    from {{ ref('int_studies') }}
    where study_id = 'qa_exclude'
) <> 1
