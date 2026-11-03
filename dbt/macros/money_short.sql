{% macro money_short(expr) -%}
case
    when abs({{ expr }}) >= 1000000 and abs({{ expr }}) % 1000000 = 0
        then '$' || cast(cast(abs({{ expr }}) / 1000000 as integer) as varchar) || 'M'
    when abs({{ expr }}) >= 1000000
        then '$' || rtrim(rtrim(cast(cast(round(abs({{ expr }}) / 1000000, 1) as decimal(10, 1)) as varchar), '0'), '.') || 'M'
    else '$' || cast(cast(round(abs({{ expr }}) / 1000, 0) as integer) as varchar) || 'k'
end
{%- endmacro %}
