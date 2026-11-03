select site_id
from {{ ref('mart_site_turnaround') }}
where (n_studies < {{ var("min_n") }} and too_few_studies <> 1)
    or (n_studies >= {{ var("min_n") }} and too_few_studies <> 0)

union all

select 'pine'
from {{ ref('mart_site_turnaround') }}
where modality = 'All'
    and site_id = 'site_nb_pine'
    and (
        n_studies >= {{ var("min_n") }}
        or too_few_studies <> 1
        or size_band <> 'tiny'
    )

union all

select site_id
from {{ ref('mart_site_turnaround') }}
where modality = 'All'
    and site_id <> 'site_nb_pine'
    and (n_studies < 500 or too_few_studies <> 0)

union all

select 'weekly_flag'
from {{ ref('mart_weekly_turnaround') }}
where (n_studies < {{ var("min_n") }} and too_few_studies <> 1)
    or (n_studies >= {{ var("min_n") }} and too_few_studies <> 0)

union all

select 'heat_flag'
from {{ ref('mart_heatmap') }}
where (n_studies < {{ var("min_n") }} and too_few_studies <> 1)
    or (n_studies >= {{ var("min_n") }} and too_few_studies <> 0)

union all

select 'main_not_slower_than_east'
from {{ ref('mart_site_turnaround') }} as main_site
inner join {{ ref('mart_site_turnaround') }} as east_site
    on main_site.modality = 'All'
    and east_site.modality = 'All'
    and main_site.site_id = 'site_nb_main'
    and east_site.site_id = 'site_nb_east'
where main_site.median_turnaround_minutes <= east_site.median_turnaround_minutes
