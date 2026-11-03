{% macro datediff_days(start_expr, end_expr) -%}
{%- if target.type == 'snowflake' -%}
datediff('day', {{ start_expr }}, {{ end_expr }})
{%- else -%}
date_diff('day', {{ start_expr }}, {{ end_expr }})
{%- endif -%}
{%- endmacro %}
