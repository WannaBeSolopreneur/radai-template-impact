"""Export governed marts, plus bootstrap intervals, for the static page.

Point estimates come from the dbt marts. The intervals are percentile
bootstraps. A group under 30 studies does not get an interval.
"""

from __future__ import annotations

import json
import os
from decimal import Decimal
from pathlib import Path

import duckdb
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
MODALITIES = ("CT", "MRI", "XR", "US")
SLICES = ("All",) + MODALITIES
MIN_N = 30


def connect():
    path = os.environ.get("RAD_DB_PATH", str(ROOT / "data" / "rad.duckdb"))
    return duckdb.connect(path, read_only=True)


def rows(con, sql: str) -> list[dict]:
    cursor = con.execute(sql)
    names = [item[0] for item in cursor.description]
    return [dict(zip(names, row)) for row in cursor.fetchall()]


def iso_day(value) -> str:
    return str(value)[:10]


def plain(value):
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        return iso_day(value)
    if isinstance(value, (bytes, bytearray)):
        return value.decode()
    if isinstance(value, Decimal):
        return float(value)
    if hasattr(value, "item"):
        value = value.item()
    if isinstance(value, float) and not np.isfinite(value):
        raise SystemExit("Non-finite number in the page export")
    return value


def table(con, sql: str) -> list[dict]:
    return [{key: plain(item) for key, item in row.items()} for row in rows(con, sql)]


def load_dashboard(con) -> dict:
    goals = table(
        con,
        """
        select
            goal_id as id,
            label,
            detail,
            unit,
            metric_kind as kind,
            current_value as currentValue,
            target_value as targetValue,
            current_label as currentLabel,
            target_label as targetLabel,
            progress_ratio as progress,
            pace_ratio as pace,
            status,
            status_label as statusLabel,
            days_elapsed as daysElapsed,
            days_in_quarter as daysInQuarter,
            sort_order as sortOrder
        from marts.mart_goal_status
        order by sort_order
        """,
    )
    actions = table(
        con,
        """
        select
            action_id as id,
            sort_order as sortOrder,
            section_id as sectionId,
            title,
            sentence
        from marts.mart_actions_this_week
        order by sort_order
        """,
    )
    if not 3 <= len(actions) <= 5:
        raise SystemExit(f"Expected 3 to 5 actions, found {len(actions)}")
    months = table(
        con,
        """
        select
            cast(month_start as varchar) as month,
            month_label as label,
            bookings_arr as bookings,
            monthly_goal as goal,
            month_note as note
        from marts.mart_monthly_bookings
        order by month_start
        """,
    )
    funnel = table(
        con,
        """
        select
            stage,
            label,
            stage_rank as rank,
            reached,
            conversion_from_previous as conversion
        from marts.mart_funnel
        order by stage_rank
        """,
    )
    wins = table(
        con,
        """
        select
            segment,
            segment_label as label,
            closed_deals as closed,
            won_deals as won,
            win_rate as rate
        from marts.mart_win_rate
        order by case segment when 'radiology_group' then 1 else 2 end
        """,
    )
    channels = table(
        con,
        """
        select
            channel,
            channel_name as name,
            spend,
            opportunities,
            pipeline_arr as pipeline,
            cost_per_opportunity as cost
        from marts.mart_channel_performance
        order by sort_order
        """,
    )
    accounts = table(
        con,
        """
        select
            account_id as id,
            account_name as name,
            segment_label as segment,
            arr,
            renewal_label as renewal,
            days_to_renewal as daysToRenewal,
            adoption_label as adoption,
            recent_ai_rate as adoptionRate,
            trend,
            trend_label as trendLabel,
            health_score as healthScore,
            health_band as healthBand,
            health_label as healthLabel,
            renewal_at_risk as renewalAtRisk
        from marts.mart_account_health
        order by display_order
        """,
    )
    saved = table(
        con,
        """
        select
            before_minutes as beforeMinutes,
            after_minutes as afterMinutes,
            minutes_faster as minutesFaster,
            caption
        from marts.mart_time_saved
        """,
    )[0]
    return {
        "goals": goals,
        "actions": actions,
        "months": months,
        "funnel": funnel,
        "wins": wins,
        "channels": channels,
        "accounts": accounts,
        "timeSaved": saved,
    }


def boot_median(values: np.ndarray, rng: np.random.Generator, draws: int):
    values = np.ascontiguousarray(values, dtype=np.float64)
    n = int(values.size)
    if n == 0:
        return None, None, None, 0
    point = float(np.median(values))
    if n < MIN_N:
        return point, None, None, n
    index = rng.integers(0, n, size=(draws, n))
    samples = np.median(values[index], axis=1)
    lo, hi = np.quantile(samples, [0.025, 0.975])
    return point, float(lo), float(hi), n


def boot_mean(values: np.ndarray, rng: np.random.Generator, draws: int):
    values = np.ascontiguousarray(values, dtype=np.float64)
    n = int(values.size)
    if n == 0:
        return None, None, None, 0
    point = float(values.mean())
    if n < MIN_N:
        return point, None, None, n
    index = rng.integers(0, n, size=(draws, n))
    samples = values[index].mean(axis=1)
    lo, hi = np.quantile(samples, [0.025, 0.975])
    return point, float(lo), float(hi), n


def boot_weighted_change(by_modality: dict, weights: dict, column: str, rng, draws: int):
    """Fixed pre-launch weights. Resample inside each modality and period."""
    before_samples = []
    after_samples = []
    for name in MODALITIES:
        before = by_modality[(name, "before")][column]
        after = by_modality[(name, "after")][column]
        before_point, _, _, before_n = boot_median(before, rng, 1)
        after_point, _, _, after_n = boot_median(after, rng, 1)
        if before_n < MIN_N or after_n < MIN_N:
            raise SystemExit(f"{name} is too small for a mix-adjusted interval")
        before_index = rng.integers(0, before_n, size=(draws, before_n))
        after_index = rng.integers(0, after_n, size=(draws, after_n))
        before_samples.append(weights[name] * np.median(before[before_index], axis=1))
        after_samples.append(weights[name] * np.median(after[after_index], axis=1))
    before_sum = np.sum(before_samples, axis=0)
    after_sum = np.sum(after_samples, axis=0)
    change = after_sum - before_sum
    return {
        "before": _band(before_sum),
        "after": _band(after_sum),
        "change": _band(change),
    }


def _band(samples: np.ndarray) -> dict:
    lo, hi = np.quantile(samples, [0.025, 0.975])
    return {"lo": float(lo), "hi": float(hi)}


def cover(point, lo, hi, label: str) -> None:
    if lo is None:
        return
    if point < lo - 0.05 or point > hi + 0.05:
        raise SystemExit(f"{label} point {point} is outside the interval {lo} to {hi}")


def pack(point, lo, hi, n, dbt_point=None) -> dict:
    shown = float(dbt_point) if dbt_point is not None else point
    if point is not None and dbt_point is not None and abs(point - float(dbt_point)) > 0.2:
        raise SystemExit(f"Bootstrap median {point} disagrees with dbt {dbt_point}")
    cover(shown, lo, hi, "interval")
    return {"value": shown, "lo": lo, "hi": hi, "n": n}


def mask_slice(modality: np.ndarray, name: str) -> np.ndarray:
    if name == "All":
        return np.ones(len(modality), dtype=bool)
    return modality == name


def main() -> None:
    con = connect()
    headline = rows(con, "select * from marts.mart_headline")[0]
    draws = int(headline["bootstrap_draws"])
    rng = np.random.default_rng(int(headline["seed"]))

    frame = con.execute(
        """
        select
            study_id,
            modality,
            period,
            cast(week_start as varchar) as week_start,
            site_id,
            turnaround_minutes,
            time_on_report_minutes,
            used_template,
            is_ai_accepted,
            is_ai_scored,
            words_dictated,
            specialty
        from marts.fct_studies_metric
        """
    ).fetchnumpy()
    order = np.argsort(frame["study_id"].astype(str), kind="mergesort")
    modality = frame["modality"].astype(str)[order]
    period = frame["period"].astype(str)[order]
    week = np.array([value[:10] for value in frame["week_start"].astype(str)])[order]
    site_id = frame["site_id"].astype(str)[order]
    turnaround = frame["turnaround_minutes"].astype(np.float64)[order]
    report = frame["time_on_report_minutes"].astype(np.float64)[order]
    used = frame["used_template"].astype(np.float64)[order]
    ai_accepted = frame["is_ai_accepted"].astype(np.float64)[order]
    ai_scored = frame["is_ai_scored"].astype(np.float64)[order]
    words = frame["words_dictated"].astype(np.float64)[order]
    specialty = frame["specialty"].astype(str)[order]

    weights = {
        row["modality"]: float(row["weight"])
        for row in rows(con, "select modality, weight from marts.mart_case_mix_weights")
    }
    by_modality = {}
    for name in MODALITIES:
        for when in ("before", "after"):
            chosen = (modality == name) & (period == when)
            by_modality[(name, when)] = {
                "turnaround": turnaround[chosen],
                "report": report[chosen],
            }

    adjusted_tat = boot_weighted_change(by_modality, weights, "turnaround", rng, draws)
    adjusted_report = boot_weighted_change(by_modality, weights, "report", rng, draws)
    cover(headline["adjusted_change_minutes"], adjusted_tat["change"]["lo"], adjusted_tat["change"]["hi"], "adjusted tat")
    cover(
        headline["adjusted_report_change_minutes"],
        adjusted_report["change"]["lo"],
        adjusted_report["change"]["hi"],
        "adjusted report",
    )
    cover(headline["adjusted_before_minutes"], adjusted_tat["before"]["lo"], adjusted_tat["before"]["hi"], "adj before")
    cover(headline["adjusted_after_minutes"], adjusted_tat["after"]["lo"], adjusted_tat["after"]["hi"], "adj after")

    after = period == "after"
    before = period == "before"
    scored = ai_scored == 1
    _, ai_lo, ai_hi, ai_n = boot_mean(ai_accepted[after & scored], rng, draws)
    _, use_lo, use_hi, use_n = boot_mean(used[after], rng, draws)
    _, words_lo, words_hi, words_n = boot_median(words[after], rng, draws)
    raw_before_point, raw_before_lo, raw_before_hi, raw_before_n = boot_median(turnaround[before], rng, draws)
    raw_after_point, raw_after_lo, raw_after_hi, raw_after_n = boot_median(turnaround[after], rng, draws)

    sites = rows(
        con,
        """
        select site_id, site_name, size_band, sort_order
        from marts.dim_site
        order by sort_order
        """,
    )
    weekly_rows = rows(
        con,
        """
        select week_start, modality, n_studies, median_turnaround_minutes, too_few_studies
        from marts.mart_weekly_turnaround
        order by week_start, modality
        """,
    )
    site_rows = rows(
        con,
        """
        select site_id, modality, n_studies, median_turnaround_minutes, too_few_studies
        from marts.mart_site_turnaround
        order by site_id, modality
        """,
    )
    heat_rows = rows(
        con,
        """
        select dow_index, exam_hour, modality, n_studies, median_turnaround_minutes, too_few_studies
        from marts.mart_heatmap
        order by modality, dow_index, exam_hour
        """,
    )
    box_rows = rows(
        con,
        """
        select modality, period, n_studies, p10, p25, p50, p75, p90, too_few_studies
        from marts.mart_modality_box
        order by modality, period
        """,
    )
    ai_rows = rows(
        con,
        """
        select modality, specialty, ai_impression_status, n_studies
        from marts.mart_ai_specialty
        order by modality, specialty, ai_impression_status
        """,
    )
    period_rows = rows(
        con,
        """
        select modality, period, n_studies, median_turnaround_minutes, too_few_studies
        from marts.mart_modality_period
        order by modality, period
        """,
    )
    period_index = {(row["modality"], row["period"]): row for row in period_rows}

    def weekly_ci(slice_name: str, week_key: str):
        chosen = mask_slice(modality, slice_name) & (week == week_key)
        point, lo, hi, n = boot_median(turnaround[chosen], rng, draws)
        return lo, hi, n, point

    def site_ci(slice_name: str, site: str):
        chosen = mask_slice(modality, slice_name) & (site_id == site)
        return boot_median(turnaround[chosen], rng, draws)

    slices = {}
    for slice_name in SLICES:
        weekly = []
        for row in sorted(
            (row for row in weekly_rows if row["modality"] == slice_name),
            key=lambda item: iso_day(item["week_start"]),
        ):
            week_key = iso_day(row["week_start"])
            lo, hi, n, point = weekly_ci(slice_name, week_key)
            too_few = int(row["too_few_studies"]) == 1 or int(row["n_studies"]) < MIN_N
            if too_few:
                lo, hi = None, None
            weekly.append(
                {
                    "week": week_key,
                    "median": float(row["median_turnaround_minutes"]),
                    "lo": lo,
                    "hi": hi,
                    "n": int(row["n_studies"]),
                    "tooFew": too_few,
                }
            )
            if not too_few:
                cover(float(row["median_turnaround_minutes"]), lo, hi, f"{slice_name} {week_key}")
                if point is not None and abs(point - float(row["median_turnaround_minutes"])) > 0.2:
                    raise SystemExit(f"Week median drift {slice_name} {week_key}")

        site_payload = []
        for site in sites:
            match = next(
                (row for row in site_rows if row["site_id"] == site["site_id"] and row["modality"] == slice_name),
                None,
            )
            n_studies = int(match["n_studies"]) if match else 0
            too_few = n_studies < MIN_N
            median = float(match["median_turnaround_minutes"]) if match and not too_few else (
                float(match["median_turnaround_minutes"]) if match else None
            )
            point, lo, hi, boot_n = site_ci(slice_name, site["site_id"])
            if too_few:
                lo, hi = None, None
            elif match and abs(point - float(match["median_turnaround_minutes"])) > 0.2:
                raise SystemExit(f"Site median drift {site['site_id']} {slice_name}")
            site_payload.append(
                {
                    "id": site["site_id"],
                    "name": site["site_name"],
                    "size": site["size_band"],
                    "n": n_studies,
                    "median": None if match is None else float(match["median_turnaround_minutes"]),
                    "lo": lo,
                    "hi": hi,
                    "tooFew": too_few,
                }
            )
            if not too_few:
                cover(float(match["median_turnaround_minutes"]), lo, hi, site["site_name"])

        if slice_name == "All":
            compare = {
                "mode": "mix",
                "rawBefore": pack(raw_before_point, raw_before_lo, raw_before_hi, raw_before_n, headline["raw_before_minutes"]),
                "rawAfter": pack(raw_after_point, raw_after_lo, raw_after_hi, raw_after_n, headline["raw_after_minutes"]),
                "adjBefore": {
                    "value": float(headline["adjusted_before_minutes"]),
                    "lo": adjusted_tat["before"]["lo"],
                    "hi": adjusted_tat["before"]["hi"],
                },
                "adjAfter": {
                    "value": float(headline["adjusted_after_minutes"]),
                    "lo": adjusted_tat["after"]["lo"],
                    "hi": adjusted_tat["after"]["hi"],
                },
            }
        else:
            before_row = period_index[(slice_name, "before")]
            after_row = period_index[(slice_name, "after")]
            b_point, b_lo, b_hi, b_n = boot_median(turnaround[(modality == slice_name) & before], rng, draws)
            a_point, a_lo, a_hi, a_n = boot_median(turnaround[(modality == slice_name) & after], rng, draws)
            compare = {
                "mode": "one",
                "rawBefore": pack(b_point, b_lo, b_hi, b_n, before_row["median_turnaround_minutes"]),
                "rawAfter": pack(a_point, a_lo, a_hi, a_n, after_row["median_turnaround_minutes"]),
            }

        group = period_index[(slice_name, "all")]
        heatmap = [
            {
                "dow": int(row["dow_index"]),
                "hour": int(row["exam_hour"]),
                "median": float(row["median_turnaround_minutes"]),
                "n": int(row["n_studies"]),
                "tooFew": int(row["too_few_studies"]) == 1,
            }
            for row in heat_rows
            if row["modality"] == slice_name
        ]
        boxes = [
            {
                "modality": row["modality"],
                "period": row["period"],
                "n": int(row["n_studies"]),
                "p10": float(row["p10"]),
                "p25": float(row["p25"]),
                "p50": float(row["p50"]),
                "p75": float(row["p75"]),
                "p90": float(row["p90"]),
                "tooFew": int(row["too_few_studies"]) == 1,
            }
            for row in box_rows
            if slice_name == "All" or row["modality"] == slice_name
        ]
        ai_index = {}
        for row in ai_rows:
            if row["modality"] != slice_name:
                continue
            bucket = ai_index.setdefault(
                row["specialty"],
                {"specialty": row["specialty"], "accepted": 0, "edited": 0, "rejected": 0},
            )
            bucket[row["ai_impression_status"]] = int(row["n_studies"])
        ai_payload = []
        for bucket in ai_index.values():
            total = bucket["accepted"] + bucket["edited"] + bucket["rejected"]
            bucket["n"] = total
            bucket["tooFew"] = total < MIN_N
            ai_payload.append(bucket)
        ai_payload.sort(key=lambda item: item["n"], reverse=True)

        slices[slice_name] = {
            "weekly": weekly,
            "sites": site_payload,
            "groupMedian": float(group["median_turnaround_minutes"]),
            "heatmap": heatmap,
            "boxes": boxes,
            "compare": compare,
            "ai": ai_payload,
        }

    payload = {
        "meta": {
            "customer": headline["customer_name"],
            "launch": iso_day(headline["launch_at"]),
            "partialStart": iso_day(headline["partial_start"]),
            "asOf": iso_day(headline["as_of"]),
            "windowStart": iso_day(headline["window_start"]),
            "windowEnd": iso_day(headline["window_end"]),
            "nStudies": int(headline["n_studies"]),
            "nBefore": int(headline["n_before"]),
            "nAfter": int(headline["n_after"]),
            "partialStudies": int(headline["partial_studies"]),
            "seed": int(headline["seed"]),
            "bootstrapDraws": draws,
            "minStudies": MIN_N,
            "mriBefore": float(headline["mri_share_before"]),
            "mriAfter": float(headline["mri_share_after"]),
            "caveat": "Last 2 days still loading, excluded.",
            "synthetic": "All data is synthetic. This is not Rad AI data.",
        },
        "headlines": {
            "reportChange": {
                "value": float(headline["adjusted_report_change_minutes"]),
                "lo": adjusted_report["change"]["lo"],
                "hi": adjusted_report["change"]["hi"],
                "before": float(headline["adjusted_report_before_minutes"]),
                "after": float(headline["adjusted_report_after_minutes"]),
            },
            "turnaroundChange": {
                "value": float(headline["adjusted_change_minutes"]),
                "lo": adjusted_tat["change"]["lo"],
                "hi": adjusted_tat["change"]["hi"],
                "before": float(headline["adjusted_before_minutes"]),
                "after": float(headline["adjusted_after_minutes"]),
            },
            "rawTurnaround": {
                "before": float(headline["raw_before_minutes"]),
                "after": float(headline["raw_after_minutes"]),
                "change": float(headline["raw_change_minutes"]),
            },
            "aiAcceptance": pack(None, ai_lo, ai_hi, ai_n, headline["ai_acceptance_after"]),
            "templateUsage": pack(None, use_lo, use_hi, use_n, headline["template_usage_after"]),
            "wordsAfter": pack(None, words_lo, words_hi, words_n, headline["median_words_after"]),
            "wordsBefore": float(headline["median_words_before"]),
        },
        "slices": slices,
        "dashboard": load_dashboard(con),
    }
    # pack() with point None skips the drift check. Rates still need a cover.
    cover(float(headline["ai_acceptance_after"]), ai_lo, ai_hi, "ai")
    cover(float(headline["template_usage_after"]), use_lo, use_hi, "usage")
    cover(float(headline["median_words_after"]), words_lo, words_hi, "words")
    cover(float(headline["raw_before_minutes"]), raw_before_lo, raw_before_hi, "raw before")
    cover(float(headline["raw_after_minutes"]), raw_after_lo, raw_after_hi, "raw after")

    pine = next(site for site in slices["All"]["sites"] if site["id"] == "site_nb_pine")
    if not pine["tooFew"] or pine["n"] >= MIN_N:
        raise SystemExit("Pine Cove should be flagged too few studies")

    encoded = json.dumps(round_numbers(payload), indent=2)
    site = ROOT / "site"
    site.mkdir(exist_ok=True)
    (site / "data.json").write_text(encoded + "\n")
    (site / "data.js").write_text("window.SITE_DATA = " + encoded + ";\n")
    print_summary(payload)
    con.close()


def round_numbers(value):
    if isinstance(value, dict):
        return {key: round_numbers(item) for key, item in value.items()}
    if isinstance(value, list):
        return [round_numbers(item) for item in value]
    if isinstance(value, float):
        if not np.isfinite(value):
            raise SystemExit("Non-finite number in the page export")
        return round(value, 4)
    return value


def print_summary(payload: dict) -> None:
    headlines = payload["headlines"]
    meta = payload["meta"]
    print(
        "Adjusted report change {value:.2f} CI {lo:.2f} to {hi:.2f}".format(
            value=headlines["reportChange"]["value"],
            lo=headlines["reportChange"]["lo"],
            hi=headlines["reportChange"]["hi"],
        )
    )
    print(
        "Adjusted turnaround change {value:.2f} CI {lo:.2f} to {hi:.2f}".format(
            value=headlines["turnaroundChange"]["value"],
            lo=headlines["turnaroundChange"]["lo"],
            hi=headlines["turnaroundChange"]["hi"],
        )
    )
    print(
        "Raw turnaround {before:.2f} to {after:.2f}".format(
            before=headlines["rawTurnaround"]["before"],
            after=headlines["rawTurnaround"]["after"],
        )
    )
    print(
        "AI {value:.3f} CI {lo:.3f} to {hi:.3f}".format(
            value=headlines["aiAcceptance"]["value"],
            lo=headlines["aiAcceptance"]["lo"],
            hi=headlines["aiAcceptance"]["hi"],
        )
    )
    print(
        "Template use {value:.3f} CI {lo:.3f} to {hi:.3f}".format(
            value=headlines["templateUsage"]["value"],
            lo=headlines["templateUsage"]["lo"],
            hi=headlines["templateUsage"]["hi"],
        )
    )
    print(
        "Studies {n} partial {partial} MRI {before:.1%} to {after:.1%}".format(
            n=meta["nStudies"],
            partial=meta["partialStudies"],
            before=meta["mriBefore"],
            after=meta["mriAfter"],
        )
    )
    for goal in payload["dashboard"]["goals"]:
        print(
            "Goal {label}: {current} of {target} ({status})".format(
                label=goal["label"],
                current=goal["currentLabel"],
                target=goal["targetLabel"],
                status=goal["statusLabel"],
            )
        )
    for action in payload["dashboard"]["actions"]:
        print("Action: " + action["sentence"])


if __name__ == "__main__":
    main()
