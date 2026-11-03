{% macro minutes_between(start_ts, end_ts) -%}
({{ seconds_between(start_ts, end_ts) }}) / 60.0
{%- endmacro %}
