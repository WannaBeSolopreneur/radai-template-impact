select study_id
from {{ ref('fct_studies') }}
where (used_template = 0 and (template_id is not null or template_version is not null))
    or (used_template = 1 and (template_id is null or template_version is null))

union all

select studies.study_id
from {{ ref('fct_studies') }} as studies
inner join {{ ref('stg_template_catalog') }} as catalog
    on studies.template_id = catalog.template_id
where studies.template_version <> catalog.template_version
    or studies.modality <> catalog.modality
    or studies.specialty <> catalog.specialty

union all

select study_id
from {{ ref('fct_studies_metric') }}
where period = 'before'
    and template_version = 'new'

union all

select 'no_adoption'
where (
    select count(*)
    from {{ ref('fct_studies_metric') }}
    where period = 'after'
        and template_version = 'new'
) < 1000
