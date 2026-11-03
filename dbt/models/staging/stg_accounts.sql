select
    account_id,
    account_name,
    segment,
    arr,
    arr_one_year_ago,
    renewal_date,
    is_active
from {{ source('raw', 'accounts') }}
