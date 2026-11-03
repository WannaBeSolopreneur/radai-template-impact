select
    adjusted_report_before_minutes as before_minutes,
    adjusted_report_after_minutes as after_minutes,
    -adjusted_report_change_minutes as minutes_faster,
    'Same mix of scans. About '
        || rtrim(
            rtrim(cast(cast(round(-adjusted_report_change_minutes, 1) as decimal(10, 1)) as varchar), '0'),
            '.'
        )
        || ' minutes faster on the report.' as caption
from {{ ref('mart_case_mix_change') }}
