{% macro week_start(ts) -%}
{%- set day = "cast(" ~ ts ~ " as date)" -%}
{%- set offset = "((dayofweek(" ~ day ~ ") + 6) % 7)" -%}
{%- if target.type == 'snowflake' -%}
dateadd('day', -1 * ({{ offset }}), {{ day }})
{%- else -%}
{{ day }} - ({{ offset }}) * interval 1 day
{%- endif -%}
{%- endmacro %}
