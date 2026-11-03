select
    quarter_start,
    quarter_end,
    funnel_start,
    win_rate_start,
    chart_start,
    on_track_ratio,
    at_risk_ratio,
    renewal_horizon_days,
    trend_points
from {{ source('raw', 'quarter') }}
