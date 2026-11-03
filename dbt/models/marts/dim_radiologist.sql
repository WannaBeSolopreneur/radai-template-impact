select
    radiologists.radiologist_id,
    radiologists.customer_id,
    radiologists.site_id,
    radiologists.radiologist_label
from {{ ref('stg_radiologists') }} as radiologists
where radiologists.customer_id = '{{ var("customer_id") }}'
    and radiologists.radiologist_id in (
        select radiologist_id
        from {{ ref('fct_studies') }}
        where customer_id = '{{ var("customer_id") }}'
    )
