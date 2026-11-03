select study_id
from {{ ref('fct_studies') }}
where is_test_fixture <> 0
    or study_id like 'qa_%'

union all

select study_id
from {{ ref('fct_studies_metric') }}
where is_test_fixture <> 0
    or study_id like 'qa_%'

union all

select 'fixtures_not_in_staging'
where (
    select count(*)
    from {{ ref('int_studies') }}
    where is_test_fixture = 1
) <> 4

union all

select 'fixture_count_meta'
where (
    select n_fixtures
    from {{ ref('stg_generation_meta') }}
) <> 4
