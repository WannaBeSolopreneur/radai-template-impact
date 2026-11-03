{% macro month_full(expr) -%}
{%- if target.type == 'snowflake' -%}
to_varchar({{ expr }}, 'MMMM')
{%- else -%}
strftime({{ expr }}, '%B')
{%- endif -%}
{%- endmacro %}
