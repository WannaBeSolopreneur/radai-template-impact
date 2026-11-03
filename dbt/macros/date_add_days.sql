{% macro date_add_days(day, n) -%}
{%- if target.type == 'snowflake' -%}
dateadd('day', {{ n }}, {{ day }})
{%- else -%}
{{ day }} + ({{ n }}) * interval 1 day
{%- endif -%}
{%- endmacro %}
