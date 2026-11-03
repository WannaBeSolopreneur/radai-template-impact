select
    goal_id,
    label,
    detail,
    unit,
    metric_kind,
    target_value,
    sort_order
from {{ source('raw', 'goals') }}
