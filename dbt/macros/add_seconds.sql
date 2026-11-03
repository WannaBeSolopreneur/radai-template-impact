{% macro add_seconds(ts, seconds_expr) -%}
{%- if target.type == 'snowflake' -%}
dateadd('second', {{ seconds_expr }}, {{ ts }})
{%- else -%}
{{ ts }} + ({{ seconds_expr }}) * interval 1 second
{%- endif -%}
{%- endmacro %}
