select
    seed,
    bootstrap_draws,
    min_studies,
    customer_id,
    cast(window_start as timestamp) as window_start,
    cast(window_end as timestamp) as window_end,
    cast(launch_at as timestamp) as launch_at,
    cast(partial_start as timestamp) as partial_start,
    cast(as_of as timestamp) as as_of,
    n_northbay_studies,
    n_northbay_partial,
    n_redcedar_studies,
    n_fixtures
from {{ source('raw', 'generation_meta') }}
