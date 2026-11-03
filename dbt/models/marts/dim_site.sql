select
    sites.site_id,
    sites.customer_id,
    sites.site_name,
    sites.size_band,
    sites.sort_order
from {{ ref('stg_sites') }} as sites
where sites.customer_id = '{{ var("customer_id") }}'
    and sites.site_id in (
        select site_id
        from {{ ref('fct_studies') }}
        where customer_id = '{{ var("customer_id") }}'
    )
