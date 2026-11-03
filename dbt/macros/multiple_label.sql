{% macro multiple_label(expr) -%}
rtrim(rtrim(cast(cast(round({{ expr }}, 1) as decimal(10, 1)) as varchar), '0'), '.') || 'x'
{%- endmacro %}
