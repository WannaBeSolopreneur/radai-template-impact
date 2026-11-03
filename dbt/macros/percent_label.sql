{% macro percent_label(expr) -%}
cast(cast(round(({{ expr }}) * 100, 0) as integer) as varchar) || '%'
{%- endmacro %}
