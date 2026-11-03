{% macro seconds_between(start_ts, end_ts) -%}
{%- if target.type == 'snowflake' -%}
datediff('second', {{ start_ts }}, {{ end_ts }})
{%- else -%}
date_diff('second', {{ start_ts }}, {{ end_ts }})
{%- endif -%}
{%- endmacro %}
