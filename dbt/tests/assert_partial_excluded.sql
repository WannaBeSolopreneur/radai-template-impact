select study_id
from {{ ref('fct_studies_metric') }}
where is_partial_period <> 0
    or exam_completed_at >= (
        select partial_start from {{ ref('stg_generation_meta') }}
    )

union all

select 'partial_count'
from {{ ref('mart_partial_period') }} as partial
cross join {{ ref('stg_generation_meta') }} as meta
where partial.partial_studies <> meta.n_northbay_partial
    or partial.partial_studies <> (
        select count(*)
        from {{ ref('fct_studies') }}
        where is_partial_period = 1
    )
    or partial.partial_studies < 20

union all

select 'metric_window_count'
from {{ ref('stg_generation_meta') }} as meta
where (
    select count(*)
    from {{ ref('fct_studies_metric') }}
) <> meta.n_northbay_studies - meta.n_northbay_partial
