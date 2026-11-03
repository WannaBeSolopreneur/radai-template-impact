select
    template_id,
    modality,
    specialty,
    template_version,
    template_name
from {{ ref('template_catalog') }}
