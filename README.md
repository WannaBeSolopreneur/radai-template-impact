# Where the quarter stands

Synthetic goals dashboard for a sales, customer success, or executive reader at a company like Rad AI. The vendor, the accounts, and the study feed are fictional.

All data is synthetic. This is not Rad AI data.

Nothing here is deployed.

## What the page says

The quarter is Q4 2026, read on day 33 of 92 (November 3). Each tile is a target, the current value, a progress bar, and a status. A pace goal is on track at 95% of a straight-line pace, at risk from 80%, and behind below that. A snapshot goal uses those cutoffs against the full target. Status and the action list are computed in dbt.

- New bookings: $540k of $2.4M, behind.
- New logos: 3 of 8, on track for the pace.
- Pipeline coverage: 2.1x of 3x, behind. Open pipeline from the meeting stage on, divided by bookings still left.
- Net revenue retention: 103.8% of 110%, at risk.
- Marketing pipeline: $1.52M of $3M, on track for the pace. Outbound is not in this goal.
- AI adoption: 76.8% of 90%, at risk. Share of reports in the last 30 complete days that used an AI impression.
- Minutes saved: 282 min of 180 min, on track. Northbay's mix-adjusted report-time change, times recent studies, divided by radiologists who read them.

Actions this week, also from the mart:

- Lakeside Imaging Group and Summit Health System renew within 60 days and AI usage is falling. Book a check-in.
- New bookings are at $540k against a $2.4M quarter goal, and the pace is behind. Review deals in contract.
- Health systems win 25% of closed deals. Radiology groups win 75%. Adjust the playbook.
- Webinars bring pipeline at the lowest cost, $1,250 per opportunity. Add one more this quarter.
- Radiologists saved about 282 min each over the last 30 days, ahead of the 180 min goal. Use that story on the next renewal.

The customer chart keeps one plain before and after for time on the report. Same mix of scans, about 2.3 minutes faster. The bootstrap interval for that change stays in the collapsed "How it's built" section.

## Run

```
make all
```

That creates a virtualenv, generates the seeded feed, runs `dbt build`, and writes `site/data.json` and `site/data.js`. Open `site/index.html`. There is no site build step. Chart.js is vendored under `site/vendor`.

## Pipeline

Study behavior lives in `assumptions/behavior.yml`. Commercial accounts, deals, spend, and goals live in `assumptions/commercial.yml`. Seed `20261103`. `rad_model/generate.py` writes a DuckDB file and `dbt/seeds/template_catalog.csv`.

dbt layers, in order:

1. Staging cleans the raw feed. Duplicate study rows keep the latest ingest. A blank modality is filled from the template catalog. A clock that starts up to 15 minutes before the exam is slid forward so signed stays at or after started, and started stays at or after the exam.
2. Intermediate joins sites, radiologists, and the launch clock, and ranks opportunity stages. It still holds every customer, including test fixtures.
3. Study marts keep one customer (`cust_northbay` by default) and drop fixtures. `fct_studies_metric` also drops the open two days. Commercial marts keep the whole book. `mart_goal_status` and `mart_actions_this_week` are the source of the tiles and the action list.

SQL stays on functions Snowflake and DuckDB share. Date arithmetic and short labels go through macros in `dbt/macros`.

## Metrics

`dbt/models/semantic.yml` is dbt Semantic Layer YAML (`semantic_models` and `metrics`), with a day time spine for the study facts.

| Metric | Definition |
| --- | --- |
| Quarterly new bookings | Closed-won ARR since the quarter started |
| New logos | First-time customers closed since the quarter started |
| Marketing-sourced pipeline | ARR on marketing-sourced deals created this quarter that reached a meeting |
| Cost per opportunity | Channel spend divided by opportunities that reached a meeting |
| Win rate by segment | Closed-won deals divided by closed-won and closed-lost deals |
| Median report turnaround | Median minutes from exam completed to signed |
| Median time on the report | Median minutes from report started to signed |
| AI impression acceptance rate | Accepted divided by accepted, edited, and rejected |
| Case-mix-adjusted time on report change | Within each modality, median time on report after minus before, then weighted by the pre-launch mix |

A negative study change is faster. Pipeline coverage, net revenue retention, portfolio AI adoption, and minutes saved per radiologist are computed in `mart_goal_status`.

## How this would be modeled in Omni

This note is a mapping only. It does not say anyone on this project has used Omni.

- A topic named Quarter goals.
- A view on `mart_goal_status` for the tiles, and a view on `mart_actions_this_week` for the action list. The page does not recompute status.
- Views on `mart_monthly_bookings`, `mart_funnel`, `mart_win_rate`, and `mart_channel_performance`.
- A view on `mart_account_health` for adoption, trend, renewal, and health score.
- A view `studies` on `fct_studies_metric` for the template story, with an access filter on `customer_id`. That is the same rule as the Snowflake row access policy example in `dbt/analyses/snowflake_row_access_policies.sql`. The policy is an example. dbt does not execute it on DuckDB.
- The case-mix change as its own view on `mart_case_mix_change`. Minutes saved per radiologist uses that change. It is not a formula typed into a workbook.

## Tests

`make all` runs `dbt build`. The build in this repo passes 248 checks, including 208 data tests. Those cover the study isolation rules from before, plus bookings, logos, coverage, retention, marketing pipeline, the pace and snapshot status rules, the funnel shape, webinar cost, win rates, the two renewal risks, and the action sentences.
