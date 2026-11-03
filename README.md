# Did the new templates actually help?

Synthetic demo for a Business Analytics Engineer, Customer Insights conversation with Rad AI. Northbay Radiology Partners is fictional. A second customer, Redcedar Imaging Alliance, exists only so isolation tests have something to keep out.

All data is synthetic. This is not Rad AI data.

This repo should stay private. Nothing here is deployed.

## What the page says

New report templates went on for Northbay on May 4, 2026. A raw median makes the launch look slower, because the group read more MRI afterward. MRI reports take longer. Comparing each modality with itself, then weighting by the pre-launch mix, shows a modest gain.

On 36,024 studies in the metric window (90 studies in the last two days are still loading and are excluded):

- Time on the report, same mix: 2.3 minutes faster (13.3 to 11.0). 95% CI 2.2 to 2.6 minutes faster.
- Report turnaround, same mix: 3.6 minutes faster (63.5 to 59.9). 95% CI 2.8 to 4.6 minutes faster.
- Raw turnaround: 45.1 minutes before the launch, 58.7 after. That rise is the mix shift, not the template.
- MRI share: 10.1% before, 29.4% after.
- AI impressions accepted after launch: 59.9% (95% CI 59.1% to 60.6%).
- Templates used after launch: 91.2% (95% CI 90.8% to 91.6%).

The template effect to quote is time on the report. Turnaround also includes the queue, and the queue is not what a template changes. Median words rose from 113 to 130 because MRI reports are longer, so word count is not a win.

Pine Cove Clinic has 24 studies. It is marked too few studies and has no interval. Groups under 30 studies are treated the same way.

## Run

```
make all
```

That creates a virtualenv, generates the seeded studies, runs `dbt build`, and writes `site/data.json` and `site/data.js`. Open `site/index.html`. There is no site build step. Chart.js is vendored under `site/vendor`.

## Pipeline

Behavior lives in `assumptions/behavior.yml` (seed `20261103`). `rad_model/generate.py` writes a DuckDB file and `dbt/seeds/template_catalog.csv`.

dbt layers, in order:

1. Staging cleans the raw feed. Duplicate study rows keep the latest ingest. A blank modality is filled from the template catalog. A clock that starts up to 15 minutes before the exam is slid forward so signed stays at or after started, and started stays at or after the exam.
2. Intermediate joins sites, radiologists, and the launch clock. It still holds every customer, including test fixtures.
3. Marts keep one customer (`cust_northbay` by default) and drop fixtures. `fct_studies_metric` also drops the open two days.

SQL stays on functions Snowflake and DuckDB share (`median`, `percentile_cont`, `qualify`, `grouping sets`). Date arithmetic goes through macros in `dbt/macros`.

## Metrics

`dbt/models/semantic.yml` is dbt Semantic Layer YAML (`semantic_models` and `metrics`), with a day time spine.

| Metric | Definition |
| --- | --- |
| Median report turnaround | Median minutes from exam completed to signed |
| Median time on the report | Median minutes from report started to signed |
| AI impression acceptance rate | Accepted divided by accepted, edited, and rejected |
| Template usage rate | Studies with a template, divided by studies |
| Words dictated per report | Median words on the report |
| Case-mix-adjusted turnaround change | Within each modality, median turnaround after minus before, then weighted by the pre-launch modality mix |
| Case-mix-adjusted time on report change | The same recipe for time on the report |

A negative change is faster. The adjusted level is a weighted average of medians, so it will not match the overall median. Intervals on the page are a 95% percentile bootstrap with 1,000 resamples. The point estimate always comes from the dbt mart. A group under 30 studies gets no interval.

## How this would be modeled in Omni

This note is a mapping only. It does not say anyone on this project has used Omni.

- A topic named Reporting performance.
- A view `studies` on `fct_studies_metric`, with measures that match the semantic metrics above.
- Dimensions for modality, specialty, priority, period, template version, site, and exam day.
- Joins from that view to `dim_site` and `dim_radiologist`.
- An access filter on `customer_id` taken from the embed user. That is the same rule as the Snowflake row access policy example in `dbt/analyses/snowflake_row_access_policies.sql`. The policy is an example. dbt does not execute it on DuckDB.
- The case-mix change as its own view on `mart_case_mix_change`. A weighted median is a tested recipe, not a formula typed into a workbook.
- `too_few_studies` greys a bar when the group has fewer than 30 studies.
- The open two days stay out of the studies view, the same way `fct_studies_metric` drops them.

## Assumptions that shape the story

- About 12 months of studies, with weekday and hour seasonality. Weekends and overnight hours are thin.
- A heavy tail on report time, so the box plots use the 10th and 90th percentiles rather than the max.
- After the launch the group reads more MRI and less XR. Each modality's own report time still falls.
- One tiny site, one large hospital that is slower than the outpatient sites, and a second customer that never appears in a mart.
- The last two days are a partial load and are excluded from every metric.
- Population clock skew is not applied. Repairing a start that was forced before the exam would also destroy the queue. One fixture, `qa_chrono`, still proves the repair rule.

## Tests

`make all` runs `dbt build`. The build in this repo passes 159 checks, including 135 data tests. Those cover uniqueness, nulls, accepted values, relationships, customer isolation, no fixtures in marts, clock order, the partial window, the case-mix identity, the headline against the fact table, and the direction of the story (raw turnaround up, mix-adjusted turnaround and time on the report down).
