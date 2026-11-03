{% macro add_months(day, n) -%}
{%- if target.type == 'snowflake' -%}
dateadd('month', {{ n }}, {{ day }})
{%- else -%}
{{ day }} + ({{ n }}) * interval 1 month
{%- endif -%}
{%- endmacro %}
