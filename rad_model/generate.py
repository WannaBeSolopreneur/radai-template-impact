"""Build the synthetic raw feed and load it into DuckDB.

The behavioral assumptions live in assumptions/behavior.yml.
Nothing in this generator is a real radiology group's data.
"""

from __future__ import annotations

import csv
import os
from pathlib import Path

import duckdb
import numpy as np
import yaml

ROOT = Path(__file__).resolve().parents[1]
ASSUMPTIONS = ROOT / "assumptions" / "behavior.yml"
RAW_DIR = ROOT / "data" / "raw"
SEED_PATH = ROOT / "dbt" / "seeds" / "template_catalog.csv"
MODALITIES = ("CT", "MRI", "XR", "US")


def load_config() -> dict:
    with ASSUMPTIONS.open() as handle:
        return yaml.safe_load(handle)


def template_id(modality: str, specialty: str, version: str) -> str:
    suffix = "v2" if version == "new" else "v1"
    return f"tpl_{modality.lower()}_{specialty.lower()}_{suffix}"


def write_catalog(cfg: dict) -> None:
    SEED_PATH.parent.mkdir(parents=True, exist_ok=True)
    with SEED_PATH.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            ["template_id", "modality", "specialty", "template_version", "template_name"]
        )
        for modality, specialties in cfg["specialties"].items():
            for specialty in specialties:
                for version, label in (("old", "v1"), ("new", "v2")):
                    writer.writerow(
                        [
                            template_id(modality, specialty, version),
                            modality,
                            specialty,
                            version,
                            f"{modality} {specialty} {label}",
                        ]
                    )


def as_ts(text: str) -> np.datetime64:
    return np.datetime64(text.replace(" ", "T"))


def dow_monday0(days: np.ndarray) -> np.ndarray:
    # 1970-01-01 was a Thursday, which is 3 when Monday is 0.
    return (days.astype("datetime64[D]").astype(np.int64) + 3) % 7


def lookup(values: np.ndarray, mapping: dict, dtype=float) -> np.ndarray:
    out = np.empty(len(values), dtype=dtype)
    missing = np.ones(len(values), dtype=bool)
    for key, mapped in mapping.items():
        mask = values == key
        out[mask] = mapped
        missing[mask] = False
    if missing.any():
        raise SystemExit(f"Missing lookup for {values[missing][:5]}")
    return out


def weighted_choice(rng: np.random.Generator, keys: list, weights: dict, n: int) -> np.ndarray:
    prob = np.array([weights[key] for key in keys], dtype=float)
    if prob.sum() <= 0:
        raise SystemExit("Weights sum to zero")
    prob = prob / prob.sum()
    return rng.choice(np.array(keys, dtype=object), size=n, p=prob)


def sample_exam_times(
    rng: np.random.Generator,
    cfg: dict,
    n: int,
    start_day: str,
    end_day: str,
    latest: np.datetime64 | None,
) -> np.ndarray:
    start = np.datetime64(start_day, "D")
    end = np.datetime64(end_day, "D")
    n_days = int((end - start) / np.timedelta64(1, "D")) + 1
    dates = start + np.arange(n_days).astype("timedelta64[D]")
    day_weights = np.array(cfg["weekday_weights"], dtype=float)[dow_monday0(dates)]
    day_p = day_weights / day_weights.sum()
    hour_p = np.array(cfg["hour_weights"], dtype=float)
    hour_p = hour_p / hour_p.sum()

    # Oversample when a same-day cutoff will reject part of the draw.
    draw_n = n if latest is None else n * 3
    picked = rng.choice(n_days, size=draw_n, p=day_p)
    hours = rng.choice(24, size=draw_n, p=hour_p)
    minutes = rng.integers(0, 60, size=draw_n)
    seconds = rng.integers(0, 60, size=draw_n)
    exam = (
        dates[picked].astype("datetime64[s]")
        + hours.astype(np.int64) * np.timedelta64(3600, "s")
        + minutes.astype(np.int64) * np.timedelta64(60, "s")
        + seconds.astype(np.int64) * np.timedelta64(1, "s")
    )
    if latest is not None:
        exam = exam[exam <= latest]
    if len(exam) < n:
        raise SystemExit(f"Only drew {len(exam)} timestamps, needed {n}")
    return np.sort(exam[:n])


def build_studies(
    rng: np.random.Generator,
    cfg: dict,
    n: int,
    customer_id: str,
    exam: np.ndarray,
    site_mode: str,
) -> dict[str, np.ndarray]:
    launch = as_ts(cfg["launch_at"])
    before = exam < launch
    modality = np.empty(n, dtype=object)
    if site_mode == "pine":
        keys = [key for key, weight in cfg["tiny_site_modality_weights"].items() if weight > 0]
        modality[:] = weighted_choice(rng, keys, cfg["tiny_site_modality_weights"], n)
    elif site_mode == "redcedar":
        keys = list(cfg["other_customer"]["modality_weights"])
        modality[:] = weighted_choice(rng, keys, cfg["other_customer"]["modality_weights"], n)
    else:
        for mask, mix in ((before, cfg["modality_mix"]["before"]), (~before, cfg["modality_mix"]["after"])):
            count = int(mask.sum())
            if count:
                modality[mask] = weighted_choice(rng, list(mix), mix, count)

    specialty = np.empty(n, dtype=object)
    for name, options in cfg["specialties"].items():
        mask = modality == name
        count = int(mask.sum())
        if count:
            specialty[mask] = rng.choice(np.array(options, dtype=object), size=count)

    site = np.empty(n, dtype=object)
    if site_mode == "pine":
        site[:] = "site_nb_pine"
    elif site_mode == "redcedar":
        keys = list(cfg["other_customer"]["site_weights"])
        site[:] = weighted_choice(rng, keys, cfg["other_customer"]["site_weights"], n)
    else:
        for name, weights in cfg["site_weights"].items():
            mask = modality == name
            count = int(mask.sum())
            if count:
                site[mask] = weighted_choice(rng, list(weights), weights, count)

    hour = (exam.astype(np.int64) % 86400) // 3600
    dow = dow_monday0(exam)
    off_hours = (hour < 7) | (hour >= 19) | (dow >= 5)
    stat_p = np.where(off_hours, cfg["stat_share_off_hours"], cfg["stat_share_day"])
    priority = np.where(rng.random(n) < stat_p, "STAT", "routine")

    roll = rng.random(n)
    version = np.full(n, "", dtype=object)
    used = np.zeros(n, dtype=int)
    before_cut = cfg["template_use"]["before"]["old"]
    after_new = cfg["template_use"]["after"]["new"]
    after_old = after_new + cfg["template_use"]["after"]["old"]
    version[before] = np.where(roll[before] < before_cut, "old", "")
    used[before] = (roll[before] < before_cut).astype(int)
    after = ~before
    version[after] = np.where(
        roll[after] < after_new,
        "new",
        np.where(roll[after] < after_old, "old", ""),
    )
    used[after] = (roll[after] < after_old).astype(int)

    templates = np.array(
        [
            template_id(modality[i], specialty[i], version[i]) if version[i] else ""
            for i in range(n)
        ],
        dtype=object,
    )

    queue_med = lookup(modality, cfg["queue_median_minutes"])
    queue_med = queue_med * lookup(site, cfg["site_queue_multiplier"])
    queue_med = queue_med * np.array(cfg["weekday_queue_multiplier"], dtype=float)[dow]
    queue_med = queue_med * np.array(cfg["hour_queue_multiplier"], dtype=float)[hour]
    queue_med = np.where(priority == "STAT", queue_med * cfg["stat_queue_multiplier"], queue_med)
    queue = np.maximum(rng.lognormal(np.log(queue_med), cfg["queue_sigma"]), 1.0)

    report_med = np.where(
        version == "new",
        lookup(modality, cfg["report_median_minutes"]["new"]),
        lookup(modality, cfg["report_median_minutes"]["old"]),
    )
    report_med = np.where(priority == "STAT", report_med * cfg["stat_report_multiplier"], report_med)
    report = rng.lognormal(np.log(report_med), cfg["report_sigma"])
    outlier = rng.random(n) < cfg["outlier_share"]
    report = np.where(
        outlier,
        report * rng.lognormal(np.log(cfg["outlier_median_multiplier"]), cfg["outlier_sigma"]),
        report,
    )
    report = np.maximum(report, 1.0)

    started = exam + np.round(queue * 60.0).astype(np.int64) * np.timedelta64(1, "s")
    signed = started + np.round(report * 60.0).astype(np.int64) * np.timedelta64(1, "s")

    word_med = np.where(
        version == "new",
        lookup(modality, cfg["words_median"]["new"]),
        lookup(modality, cfg["words_median"]["old"]),
    )
    words = np.maximum(np.rint(rng.lognormal(np.log(word_med), cfg["words_sigma"])), 20).astype(int)

    ai = np.full(n, "", dtype=object)
    ran = rng.random(n) >= cfg["ai_not_run_share"]
    uniform = rng.random(n)
    for name, bonus in cfg["ai_specialty_accept_bonus"].items():
        mask = ran & (specialty == name)
        if not mask.any():
            continue
        # Free text uses the "none" rates. Old and new templates use their own rates.
        for kind, rate_key in (("new", "new"), ("old", "old"), ("", "none")):
            sub = mask & (version == kind)
            count = int(sub.sum())
            if not count:
                continue
            accepted = min(max(cfg["ai_rates"][rate_key]["accepted"] + bonus, 0.05), 0.90)
            edited = cfg["ai_rates"][rate_key]["edited"]
            rejected = cfg["ai_rates"][rate_key]["rejected"]
            rest = edited + rejected
            edited = edited / rest * (1.0 - accepted)
            rejected = rejected / rest * (1.0 - accepted)
            draw = uniform[sub]
            status = np.full(count, "rejected", dtype=object)
            status[draw < accepted + edited] = "edited"
            status[draw < accepted] = "accepted"
            ai[sub] = status

    radiologist = np.empty(n, dtype=object)
    for site_id, count in cfg["radiologists"].items():
        mask = site == site_id
        size = int(mask.sum())
        if not size:
            continue
        labels = [f"rad_{site_id}_{i:02d}" for i in range(1, count + 1)]
        radiologist[mask] = rng.choice(np.array(labels, dtype=object), size=size)

    return {
        "customer_id": np.full(n, customer_id, dtype=object),
        "site_id": site,
        "radiologist_id": radiologist,
        "modality": modality,
        "specialty": specialty,
        "priority": priority,
        "exam_completed_at": exam,
        "report_started_at": started,
        "report_signed_at": signed,
        "template_id": templates,
        "template_version": version,
        "used_template": used,
        "words_dictated": words,
        "ai_impression_status": ai,
        "is_test_fixture": np.zeros(n, dtype=int),
        "queue_minutes": queue,
        "report_minutes": report,
    }


def concat_studies(parts: list[dict]) -> dict[str, np.ndarray]:
    keys = parts[0].keys()
    return {key: np.concatenate([part[key] for part in parts]) for key in keys}


def stamp(value: np.datetime64) -> str:
    return str(value.astype("datetime64[s]")).replace("T", " ")


def apply_mess(rng: np.random.Generator, cfg: dict, clean: dict) -> dict:
    n = len(clean["exam_completed_at"])
    raw = {key: clean[key].copy() for key in clean}
    order = rng.permutation(n)
    mess = cfg["mess"]
    n_dupe = int(round(n * mess["duplicate_share"]))
    n_blank = int(round(n * mess["blank_modality_share"]))
    n_skew = int(round(n * mess["clock_skew_share"]))
    dupe_idx = order[:n_dupe]
    blank_idx = order[n_dupe : n_dupe + n_blank]

    # Only blank a modality when a template can fill it back in.
    blank_idx = blank_idx[raw["used_template"][blank_idx] == 1]
    raw["modality"][blank_idx] = ""

    # Population rows are not given a clock skew. A skew that crosses the exam
    # time cannot be undone without eating the queue. qa_chrono is the fixture
    # that proves the repair rule. n_skew stays in the file so the rate is documented.
    _ = n_skew

    ingested = clean["exam_completed_at"] + np.timedelta64(6, "h")
    raw["ingested_at"] = ingested
    raw["source_row"] = np.arange(1, n + 1)

    copies = {key: raw[key][dupe_idx].copy() for key in raw}
    # The earlier copy is wrong on purpose. Staging keeps the later ingest.
    copies["modality"] = rng.choice(np.array(MODALITIES, dtype=object), size=len(dupe_idx))
    copies["words_dictated"] = np.maximum(copies["words_dictated"] // 2, 20)
    copies["ingested_at"] = raw["ingested_at"][dupe_idx] - np.timedelta64(2, "h")
    copies["source_row"] = np.arange(n + 1, n + 1 + len(dupe_idx))

    merged = {}
    for key in raw:
        merged[key] = np.concatenate([raw[key], copies[key]])
    return merged


def fixture_rows(cfg: dict) -> list[dict]:
    # Hand-built rows. qa_chrono is five minutes early on both report clocks.
    # qa_duplicate keeps the later CT row. qa_modality is filled from the template.
    # qa_exclude is a valid study that must never reach a mart.
    base = dict(
        customer_id=cfg["customer_id"],
        site_id="site_nb_main",
        radiologist_id="rad_site_nb_main_01",
        specialty="Chest",
        priority="routine",
        used_template=1,
        words_dictated=150,
        ai_impression_status="accepted",
        is_test_fixture=1,
    )
    rows = [
        {
            **base,
            "study_id": "qa_chrono",
            "modality": "CT",
            "exam_completed_at": "2026-06-01 10:00:00",
            "report_started_at": "2026-06-01 09:55:00",
            "report_signed_at": "2026-06-01 10:17:00",
            "template_id": "tpl_ct_chest_v2",
            "template_version": "new",
            "ingested_at": "2026-06-01 16:00:00",
            "source_row": 9000001,
        },
        {
            **base,
            "study_id": "qa_duplicate",
            "modality": "XR",
            "specialty": "Chest",
            "exam_completed_at": "2026-06-02 11:00:00",
            "report_started_at": "2026-06-02 11:20:00",
            "report_signed_at": "2026-06-02 11:32:00",
            "template_id": "tpl_xr_chest_v2",
            "template_version": "new",
            "words_dictated": 80,
            "ingested_at": "2026-06-02 12:00:00",
            "source_row": 9000002,
        },
        {
            **base,
            "study_id": "qa_duplicate",
            "modality": "CT",
            "exam_completed_at": "2026-06-02 11:00:00",
            "report_started_at": "2026-06-02 11:25:00",
            "report_signed_at": "2026-06-02 11:40:00",
            "template_id": "tpl_ct_chest_v2",
            "template_version": "new",
            "words_dictated": 160,
            "ingested_at": "2026-06-02 18:00:00",
            "source_row": 9000003,
        },
        {
            **base,
            "study_id": "qa_modality",
            "modality": "",
            "specialty": "Neuro",
            "exam_completed_at": "2026-06-03 09:00:00",
            "report_started_at": "2026-06-03 09:40:00",
            "report_signed_at": "2026-06-03 10:05:00",
            "template_id": "tpl_mri_neuro_v2",
            "template_version": "new",
            "words_dictated": 210,
            "ingested_at": "2026-06-03 15:00:00",
            "source_row": 9000004,
        },
        {
            **base,
            "study_id": "qa_exclude",
            "modality": "US",
            "specialty": "Breast",
            "site_id": "site_nb_hill",
            "radiologist_id": "rad_site_nb_hill_01",
            "exam_completed_at": "2026-06-04 13:00:00",
            "report_started_at": "2026-06-04 13:30:00",
            "report_signed_at": "2026-06-04 13:42:00",
            "template_id": "tpl_us_breast_v2",
            "template_version": "new",
            "words_dictated": 100,
            "ingested_at": "2026-06-04 18:00:00",
            "source_row": 9000005,
        },
    ]
    return rows


def write_table(path: Path, header: list[str], rows: list[list]) -> None:
    with path.open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows(rows)


STUDY_HEADER = [
    "study_id",
    "customer_id",
    "site_id",
    "radiologist_id",
    "modality",
    "specialty",
    "priority",
    "exam_completed_at",
    "report_started_at",
    "report_signed_at",
    "template_id",
    "template_version",
    "used_template",
    "words_dictated",
    "ai_impression_status",
    "is_test_fixture",
    "ingested_at",
    "source_row",
]


def check_story(cfg: dict, clean: dict) -> None:
    partial = as_ts(cfg["partial_start"])
    launch = as_ts(cfg["launch_at"])
    keep = (clean["customer_id"] == cfg["customer_id"]) & (clean["exam_completed_at"] < partial)
    exam = clean["exam_completed_at"][keep]
    modality = clean["modality"][keep]
    tat = (clean["queue_minutes"] + clean["report_minutes"])[keep]
    report = clean["report_minutes"][keep]
    before = exam < launch
    after = ~before

    queue = clean["queue_minutes"][keep]

    def med(mask: np.ndarray) -> float:
        return float(np.median(tat[mask]))

    def med_report(mask: np.ndarray) -> float:
        return float(np.median(report[mask]))

    weights = {}
    print("Northbay metric window", int(keep.sum()))
    print(f"  raw TAT before {med(before):.2f} after {med(after):.2f} change {med(after) - med(before):.2f}")
    print(
        f"  time on report before {med_report(before):.2f} after {med_report(after):.2f} "
        f"change {med_report(after) - med_report(before):.2f}"
    )
    adj_before = 0.0
    adj_after = 0.0
    for name in MODALITIES:
        both = modality == name
        share = float(both[before].sum() / before.sum())
        weights[name] = share
        tat_before = float(np.median(tat[before & both]))
        tat_after = float(np.median(tat[after & both]))
        rep_before = float(np.median(report[before & both]))
        rep_after = float(np.median(report[after & both]))
        q_before = float(np.median(queue[before & both]))
        q_after = float(np.median(queue[after & both]))
        adj_before += share * tat_before
        adj_after += share * tat_after
        print(
            f"  {name} share before {share:.3f} after {float(both[after].sum() / after.sum()):.3f} "
            f"TAT {tat_before:.2f}->{tat_after:.2f} report {rep_before:.2f}->{rep_after:.2f} "
            f"queue {q_before:.2f}->{q_after:.2f} n {int(both.sum())}"
        )
        if not rep_after < rep_before - 0.4:
            raise SystemExit(f"{name} report time did not fall enough")
        if not tat_after < tat_before:
            raise SystemExit(f"{name} turnaround did not fall inside the modality")
    mri_before = float(((modality == "MRI") & before).sum() / before.sum())
    mri_after = float(((modality == "MRI") & after).sum() / after.sum())
    raw_change = med(after) - med(before)
    adj_change = adj_after - adj_before
    report_change = med_report(after) - med_report(before)
    print(f"  MRI share {mri_before:.3f} -> {mri_after:.3f}")
    print(f"  adjusted TAT {adj_before:.2f} -> {adj_after:.2f} change {adj_change:.2f}")
    print(f"  weights {weights}")
    if raw_change <= 5:
        raise SystemExit("Raw turnaround did not look slower. Raise the MRI shift or the MRI queue.")
    if adj_change >= -0.5:
        raise SystemExit("Adjusted turnaround did not look faster.")
    # The raw median of time on report can sit still when MRI grows, because MRI reports are longer.
    # The mix-adjusted change is the one that has to move.
    adj_report = 0.0
    for name in MODALITIES:
        both = modality == name
        adj_report += weights[name] * (
            float(np.median(report[after & both])) - float(np.median(report[before & both]))
        )
    print(f"  adjusted report change {adj_report:.2f}")
    if adj_report >= -1:
        raise SystemExit("Mix-adjusted time on report did not fall by at least a minute.")
    if mri_after - mri_before <= 0.10:
        raise SystemExit("MRI mix shift is too small.")
    print("Story checks passed.")


def load_duckdb(cfg: dict, paths: dict[str, Path]) -> None:
    db_path = Path(os.environ.get("RAD_DB_PATH", ROOT / "data" / "rad.duckdb"))
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()
    wal = Path(str(db_path) + ".wal")
    if wal.exists():
        wal.unlink()
    con = duckdb.connect(str(db_path))
    con.execute("create schema raw")
    specs = {
        "customers": """
            customer_id varchar,
            customer_name varchar
        """,
        "sites": """
            site_id varchar,
            customer_id varchar,
            site_name varchar,
            size_band varchar,
            sort_order integer
        """,
        "radiologists": """
            radiologist_id varchar,
            customer_id varchar,
            site_id varchar,
            radiologist_label varchar
        """,
        "studies": """
            study_id varchar,
            customer_id varchar,
            site_id varchar,
            radiologist_id varchar,
            modality varchar,
            specialty varchar,
            priority varchar,
            exam_completed_at timestamp,
            report_started_at timestamp,
            report_signed_at timestamp,
            template_id varchar,
            template_version varchar,
            used_template integer,
            words_dictated integer,
            ai_impression_status varchar,
            is_test_fixture integer,
            ingested_at timestamp,
            source_row integer
        """,
        "generation_meta": """
            seed integer,
            bootstrap_draws integer,
            min_studies integer,
            customer_id varchar,
            window_start timestamp,
            window_end timestamp,
            launch_at timestamp,
            partial_start timestamp,
            as_of timestamp,
            n_northbay_studies integer,
            n_northbay_partial integer,
            n_redcedar_studies integer,
            n_fixtures integer
        """,
        "accounts": """
            account_id varchar,
            account_name varchar,
            segment varchar,
            arr integer,
            arr_one_year_ago integer,
            renewal_date date,
            is_active integer
        """,
        "opportunities": """
            opportunity_id varchar,
            account_id varchar,
            prospect_name varchar,
            segment varchar,
            stage varchar,
            furthest_stage varchar,
            outcome varchar,
            arr integer,
            channel varchar,
            is_marketing_sourced integer,
            is_new_logo integer,
            created_at timestamp,
            closed_at timestamp
        """,
        "marketing_spend": """
            channel varchar,
            channel_name varchar,
            spend integer,
            sort_order integer
        """,
        "goals": """
            goal_id varchar,
            label varchar,
            detail varchar,
            unit varchar,
            metric_kind varchar,
            target_value double,
            sort_order integer
        """,
        "quarter": """
            quarter_start date,
            quarter_end date,
            funnel_start date,
            win_rate_start date,
            chart_start date,
            on_track_ratio double,
            at_risk_ratio double,
            renewal_horizon_days integer,
            trend_points double
        """,
    }
    for name, columns in specs.items():
        con.execute(f"create table raw.{name} ({columns})")
        file_path = str(paths[name]).replace("'", "''")
        con.execute(
            f"insert into raw.{name} select * from read_csv('{file_path}', header=true, nullstr='')"
        )
    counts = con.execute(
        """
        select customer_id, count(*)
        from raw.studies
        where is_test_fixture = 0
        group by 1
        order by 1
        """
    ).fetchall()
    print("Raw non-fixture rows by customer", counts)
    con.close()


def main() -> None:
    cfg = load_config()
    write_catalog(cfg)
    rng = np.random.default_rng(cfg["seed"])

    # Monday checks so the launch marker lands on a week start.
    if int(dow_monday0(np.array([np.datetime64("2025-11-03", "D")]))[0]) != 0:
        raise SystemExit("Window start is not a Monday")
    if int(dow_monday0(np.array([np.datetime64("2026-05-04", "D")]))[0]) != 0:
        raise SystemExit("Launch is not a Monday")

    window_end = as_ts(cfg["window_end"])
    full = build_studies(
        rng,
        cfg,
        cfg["n_studies"],
        cfg["customer_id"],
        sample_exam_times(rng, cfg, cfg["n_studies"], "2025-11-03", "2026-10-31", None),
        "main",
    )
    pine = build_studies(
        rng,
        cfg,
        cfg["tiny_site_n"],
        cfg["customer_id"],
        sample_exam_times(rng, cfg, cfg["tiny_site_n"], "2025-11-03", "2026-10-31", None),
        "pine",
    )
    partial = build_studies(
        rng,
        cfg,
        cfg["partial_studies"],
        cfg["customer_id"],
        sample_exam_times(rng, cfg, cfg["partial_studies"], "2026-11-01", "2026-11-02", window_end),
        "main",
    )
    redcedar = build_studies(
        rng,
        cfg,
        cfg["other_customer_studies"],
        cfg["other_customer_id"],
        sample_exam_times(rng, cfg, cfg["other_customer_studies"], "2025-11-03", "2026-10-31", None),
        "redcedar",
    )
    clean = concat_studies([full, pine, partial, redcedar])
    check_story(cfg, clean)

    clean_ids = []
    nb_i = 1
    rc_i = 1
    for customer in clean["customer_id"]:
        if customer == cfg["customer_id"]:
            clean_ids.append(f"nb_{nb_i:07d}")
            nb_i += 1
        else:
            clean_ids.append(f"rc_{rc_i:07d}")
            rc_i += 1
    clean["study_id"] = np.array(clean_ids, dtype=object)
    messed = apply_mess(rng, cfg, clean)
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    rows = []
    for i in range(len(messed["study_id"])):
        rows.append(
            [
                messed["study_id"][i],
                messed["customer_id"][i],
                messed["site_id"][i],
                messed["radiologist_id"][i],
                messed["modality"][i],
                messed["specialty"][i],
                messed["priority"][i],
                stamp(messed["exam_completed_at"][i]),
                stamp(messed["report_started_at"][i]),
                stamp(messed["report_signed_at"][i]),
                messed["template_id"][i],
                messed["template_version"][i],
                int(messed["used_template"][i]),
                int(messed["words_dictated"][i]),
                messed["ai_impression_status"][i],
                int(messed["is_test_fixture"][i]),
                stamp(messed["ingested_at"][i]),
                int(messed["source_row"][i]),
            ]
        )
    for fixture in fixture_rows(cfg):
        rows.append([fixture[column] for column in STUDY_HEADER])

    from rad_model.commercial import build_commercial

    extra = build_commercial(RAW_DIR)
    rows.extend(extra["studies"])

    write_table(RAW_DIR / "studies.csv", STUDY_HEADER, rows)
    write_table(
        RAW_DIR / "customers.csv",
        ["customer_id", "customer_name"],
        [
            [cfg["customer_id"], cfg["customer_name"]],
            [cfg["other_customer_id"], cfg["other_customer_name"]],
        ]
        + extra["customers"],
    )
    write_table(
        RAW_DIR / "sites.csv",
        ["site_id", "customer_id", "site_name", "size_band", "sort_order"],
        [
            [site["id"], site["customer"], site["name"], site["size"], site["sort"]]
            for site in cfg["sites"]
        ]
        + extra["sites"],
    )
    rad_rows = []
    for site in cfg["sites"]:
        for i in range(1, cfg["radiologists"][site["id"]] + 1):
            rad_rows.append(
                [
                    f"rad_{site['id']}_{i:02d}",
                    site["customer"],
                    site["id"],
                    f"Rad {i:02d}",
                ]
            )
    rad_rows.extend(extra["radiologists"])
    write_table(
        RAW_DIR / "radiologists.csv",
        ["radiologist_id", "customer_id", "site_id", "radiologist_label"],
        rad_rows,
    )
    write_table(
        RAW_DIR / "generation_meta.csv",
        [
            "seed",
            "bootstrap_draws",
            "min_studies",
            "customer_id",
            "window_start",
            "window_end",
            "launch_at",
            "partial_start",
            "as_of",
            "n_northbay_studies",
            "n_northbay_partial",
            "n_redcedar_studies",
            "n_fixtures",
        ],
        [
            [
                cfg["seed"],
                cfg["bootstrap_draws"],
                cfg["min_studies"],
                cfg["customer_id"],
                cfg["window_start"],
                cfg["window_end"],
                cfg["launch_at"],
                cfg["partial_start"],
                cfg["as_of"],
                cfg["n_studies"] + cfg["tiny_site_n"] + cfg["partial_studies"],
                cfg["partial_studies"],
                cfg["other_customer_studies"],
                4,
            ]
        ],
    )
    load_duckdb(
        cfg,
        {
            "customers": RAW_DIR / "customers.csv",
            "sites": RAW_DIR / "sites.csv",
            "radiologists": RAW_DIR / "radiologists.csv",
            "studies": RAW_DIR / "studies.csv",
            "generation_meta": RAW_DIR / "generation_meta.csv",
            "accounts": RAW_DIR / "accounts.csv",
            "opportunities": RAW_DIR / "opportunities.csv",
            "marketing_spend": RAW_DIR / "marketing_spend.csv",
            "goals": RAW_DIR / "goals.csv",
            "quarter": RAW_DIR / "quarter.csv",
        },
    )
    print(f"Loaded {len(rows)} raw study rows.")


if __name__ == "__main__":
    main()
