with bounds as (
    select
        cast(meta.as_of as date) as as_of,
        meta.partial_start
    from {{ ref('stg_generation_meta') }} as meta
)

select
    studies.study_id,
    studies.customer_id as account_id,
    studies.exam_completed_at,
    studies.radiologist_id,
    case
        when studies.ai_impression_status in ('accepted', 'edited') then 1
        else 0
    end as ai_used
from {{ ref('int_studies') }} as studies
inner join {{ ref('stg_accounts') }} as accounts
    on studies.customer_id = accounts.account_id
    and accounts.is_active = 1
cross join bounds
where studies.is_test_fixture = 0
    and studies.is_partial_period = 0
    and studies.exam_completed_at >= cast({{ date_add_days('bounds.as_of', -30) }} as timestamp)
    and studies.exam_completed_at < bounds.partial_start
