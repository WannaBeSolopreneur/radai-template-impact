{% macro month_abbr(expr) -%}
{%- if target.type == 'snowflake' -%}
initcap(to_varchar({{ expr }}, 'MON'))
{%- else -%}
strftime({{ expr }}, '%b')
{%- endif -%}
{%- endmacro %}
