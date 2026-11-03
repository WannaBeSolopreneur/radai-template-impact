"""Expand assumptions/commercial.yml into raw commercial tables and usage studies.

The study clock for Northbay is left untouched. These rows are appended after it.
"""

from __future__ import annotations

import csv
from datetime import datetime, timedelta
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
COMMERCIAL = ROOT / "assumptions" / "commercial.yml"
PRIOR_START = datetime(2026, 9, 4)
PRIOR_END = datetime(2026, 10, 4)
RECENT_START = datetime(2026, 10, 4)
RECENT_END = datetime(2026, 11, 1)
STAGE_RANK = {
    "lead": 1,
    "meeting": 2,
    "demo": 3,
    "pilot": 4,
    "contract": 5,
    "won": 6,
}


def load_commercial() -> dict:
    with COMMERCIAL.open() as handle:
        return yaml.safe_load(handle)


def _stamp(value: datetime) -> str:
    return value.strftime("%Y-%m-%d %H:%M:%S")


def _day(text: str) -> str:
    return f"{text} 00:00:00"


def _marketing(channel: str) -> int:
    return 0 if channel == "outbound" else 1


def _split(total: int, n: int) -> list[int]:
    if n <= 0:
        return []
    base = total // n
    amounts = [base] * n
    amounts[-1] += total - base * n
    return amounts


def _stages(channel: dict) -> list[str]:
    stages = (
        ["meeting"] * int(channel["meeting"])
        + ["demo"] * int(channel["demo"])
        + ["pilot"] * int(channel["pilot"])
    )
    if len(stages) != int(channel["q4_open_opps"]):
        raise SystemExit(f"{channel['id']} stage mix does not match the opportunity count")
    return stages


def _opp(
    opp_id: str,
    segment: str,
    stage: str,
    arr: int,
    channel: str,
    created: str,
    closed: str = "",
    account: str = "",
    new_logo: int = 0,
    name: str = "",
) -> dict:
    furthest = "won" if stage == "won" else stage
    if stage == "lost":
        raise SystemExit("Lost rows must pass the furthest stage, not lost")
    return {
        "opportunity_id": opp_id,
        "account_id": account,
        "prospect_name": name or opp_id,
        "segment": segment,
        "stage": stage,
        "furthest_stage": furthest,
        "outcome": "won" if stage == "won" else "open",
        "arr": int(arr),
        "channel": channel,
        "is_marketing_sourced": _marketing(channel),
        "is_new_logo": int(new_logo),
        "created_at": _day(created),
        "closed_at": _day(closed) if closed else "",
    }


def _lost(opp_id: str, segment: str, index: int) -> dict:
    created = datetime(2026, 6, 3) + timedelta(days=7 * index)
    closed = created + timedelta(days=21)
    row = _opp(
        opp_id,
        segment,
        "demo",
        120000,
        "outbound",
        created.strftime("%Y-%m-%d"),
        name=f"{segment} loss {index + 1}",
    )
    row["stage"] = "lost"
    row["outcome"] = "lost"
    row["furthest_stage"] = "demo"
    row["closed_at"] = _stamp(closed)
    row["created_at"] = _stamp(created)
    return row


def build_opportunities(cfg: dict) -> list[dict]:
    rows: list[dict] = []
    for deal in cfg["q4_wins"]:
        rows.append(
            _opp(
                deal["id"],
                deal["segment"],
                "won",
                deal["arr"],
                deal["channel"],
                deal["created"],
                deal["closed"],
                account=deal["account"],
                new_logo=deal["new_logo"],
                name=deal["account"],
            )
        )
    for deal in cfg["history_wins"]:
        rows.append(
            _opp(
                deal["id"],
                deal["segment"],
                "won",
                deal["arr"],
                deal["channel"],
                deal["created"],
                deal["closed"],
                name=deal["id"],
            )
        )
    for deal in cfg["older_open"]:
        rows.append(
            _opp(
                deal["id"],
                deal["segment"],
                deal["stage"],
                deal["arr"],
                deal["channel"],
                deal["created"],
                name=deal["id"],
            )
        )
    for channel in cfg["channels"]:
        amounts = _split(int(channel["q4_open_arr"]), int(channel["q4_open_opps"]))
        for index, (amount, stage) in enumerate(zip(amounts, _stages(channel))):
            created = datetime(2026, 10, 3) + timedelta(days=index)
            rows.append(
                _opp(
                    f"opp_{channel['id']}_{index + 1:02d}",
                    "radiology_group" if index % 2 == 0 else "health_system",
                    stage,
                    amount,
                    channel["id"],
                    created.strftime("%Y-%m-%d"),
                    name=f"{channel['name']} {index + 1}",
                )
            )
    for index in range(int(cfg["losses"]["radiology_group"])):
        rows.append(_lost(f"opp_loss_rad_{index + 1:02d}", "radiology_group", index))
    offset = int(cfg["losses"]["radiology_group"])
    for index in range(int(cfg["losses"]["health_system"])):
        rows.append(_lost(f"opp_loss_hs_{index + 1:02d}", "health_system", offset + index))
    for index in range(int(cfg["lead_only"])):
        created = datetime(2026, 7, 6) + timedelta(days=3 * index)
        rows.append(
            _opp(
                f"opp_lead_{index + 1:02d}",
                "radiology_group" if index % 2 == 0 else "health_system",
                "lead",
                0,
                "website",
                created.strftime("%Y-%m-%d"),
                name=f"Lead {index + 1}",
            )
        )
    ids = [row["opportunity_id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise SystemExit("Duplicate opportunity ids")
    _check_opportunities(cfg, rows)
    return rows


def _check_opportunities(cfg: dict, rows: list[dict]) -> None:
    quarter_start = datetime.fromisoformat(cfg["quarter_start"])
    as_of = datetime(2026, 11, 3)
    wins = [
        row for row in rows
        if row["outcome"] == "won" and quarter_start <= datetime.fromisoformat(row["closed_at"][:10]) < as_of
    ]
    bookings = sum(row["arr"] for row in wins)
    logos = sum(row["is_new_logo"] for row in wins)
    if bookings != 540000 or logos != 3:
        raise SystemExit(f"Q4 bookings {bookings} logos {logos}")
    open_rows = [row for row in rows if row["outcome"] == "open" and row["stage"] != "lead"]
    open_arr = sum(row["arr"] for row in open_rows)
    if open_arr != 3940000:
        raise SystemExit(f"Open pipeline {open_arr}")
    q4_open_start = quarter_start
    marketing = 0
    costs = {}
    for channel in cfg["channels"]:
        created = [
            row for row in rows
            if row["channel"] == channel["id"]
            and datetime.fromisoformat(row["created_at"][:10]) >= q4_open_start
            and datetime.fromisoformat(row["created_at"][:10]) < as_of
            and STAGE_RANK[row["furthest_stage"]] >= STAGE_RANK["meeting"]
        ]
        arr = sum(row["arr"] for row in created)
        if channel["id"] != "outbound":
            marketing += arr
        costs[channel["id"]] = channel["spend"] / len(created)
        expected_opps = int(channel["q4_open_opps"]) + (
            1 if any(row["channel"] == channel["id"] and row["outcome"] == "won" for row in wins) else 0
        )
        if len(created) != expected_opps:
            raise SystemExit(f"{channel['id']} has {len(created)} opportunities, expected {expected_opps}")
    if marketing != 1520000:
        raise SystemExit(f"Marketing pipeline {marketing}")
    if min(costs, key=costs.get) != "webinars":
        raise SystemExit(f"Cheapest channel is {min(costs, key=costs.get)}")
    win_start = datetime.fromisoformat(cfg["win_rate_start"])
    closed = [
        row for row in rows
        if row["outcome"] in ("won", "lost")
        and win_start <= datetime.fromisoformat(row["closed_at"][:10]) < as_of
    ]
    for segment, won_expected, closed_expected in (
        ("radiology_group", 12, 16),
        ("health_system", 3, 12),
    ):
        group = [row for row in closed if row["segment"] == segment]
        won = sum(1 for row in group if row["outcome"] == "won")
        if won != won_expected or len(group) != closed_expected:
            raise SystemExit(f"{segment} win {won} of {len(group)}")
    year_ago = sum(int(row["arr_one_year_ago"]) for row in cfg["accounts"])
    current = sum(
        int(row["arr"]) for row in cfg["accounts"] if int(row["arr_one_year_ago"]) > 0
    )
    if year_ago != 6900000 or current != 7160000:
        raise SystemExit(f"NRR inputs current {current} year ago {year_ago}")


def _spread(start: datetime, end: datetime, n: int) -> list[datetime]:
    span = (end - start).total_seconds()
    return [start + timedelta(seconds=span * (index + 0.5) / n) for index in range(n)]


def build_usage(cfg: dict) -> tuple[list[list], list[list], list[list], list[list]]:
    customers = []
    sites = []
    radiologists = []
    studies = []
    source_row = 900000
    for account in cfg["accounts"]:
        if account["id"] == "cust_northbay":
            continue
        customers.append([account["id"], account["name"]])
        recent_n = int(account.get("recent_n") or 0)
        prior_n = int(account.get("prior_n") or 0)
        rad_n = int(account.get("radiologists") or 0)
        if recent_n == 0 and prior_n == 0:
            continue
        site_id = "site_" + account["id"].replace("acct_", "")
        size = "large" if account["segment"] == "health_system" else "medium"
        sites.append([site_id, account["id"], account["name"], size, 20 + len(sites)])
        rad_ids = []
        for index in range(1, rad_n + 1):
            rad_id = f"rad_{site_id}_{index:02d}"
            rad_ids.append(rad_id)
            radiologists.append([rad_id, account["id"], site_id, f"Rad {index:02d}"])
        if not rad_ids:
            raise SystemExit(f"{account['id']} has studies and no radiologists")

        def add_window(start, end, n, ai_count, label):
            nonlocal source_row
            times = _spread(start, end, n)
            for index, exam in enumerate(times):
                started = exam + timedelta(minutes=15)
                signed = started + timedelta(minutes=12)
                status = "accepted" if index < ai_count else ""
                studies.append(
                    [
                        f"port_{account['id']}_{label}_{index + 1:04d}",
                        account["id"],
                        site_id,
                        rad_ids[index % len(rad_ids)],
                        "XR",
                        "MSK",
                        "routine",
                        _stamp(exam),
                        _stamp(started),
                        _stamp(signed),
                        "tpl_xr_msk_v2",
                        "new",
                        1,
                        80,
                        status,
                        0,
                        _stamp(signed),
                        source_row,
                    ]
                )
                source_row += 1

        if prior_n:
            add_window(PRIOR_START, PRIOR_END, prior_n, int(account["prior_ai"]), "prior")
        if recent_n:
            add_window(RECENT_START, RECENT_END, recent_n, int(account["recent_ai"]), "recent")
    return customers, sites, radiologists, studies


def write_commercial_tables(raw_dir: Path, cfg: dict, opportunities: list[dict]) -> None:
    raw_dir.mkdir(parents=True, exist_ok=True)

    def write(name: str, header: list[str], rows: list[list]) -> None:
        with (raw_dir / name).open("w", newline="") as handle:
            writer = csv.writer(handle)
            writer.writerow(header)
            writer.writerows(rows)

    write(
        "accounts.csv",
        [
            "account_id",
            "account_name",
            "segment",
            "arr",
            "arr_one_year_ago",
            "renewal_date",
            "is_active",
        ],
        [
            [
                row["id"],
                row["name"],
                row["segment"],
                row["arr"],
                row["arr_one_year_ago"],
                row["renewal"],
                row["active"],
            ]
            for row in cfg["accounts"]
        ],
    )
    write(
        "opportunities.csv",
        [
            "opportunity_id",
            "account_id",
            "prospect_name",
            "segment",
            "stage",
            "furthest_stage",
            "outcome",
            "arr",
            "channel",
            "is_marketing_sourced",
            "is_new_logo",
            "created_at",
            "closed_at",
        ],
        [[row[column] for column in [
            "opportunity_id",
            "account_id",
            "prospect_name",
            "segment",
            "stage",
            "furthest_stage",
            "outcome",
            "arr",
            "channel",
            "is_marketing_sourced",
            "is_new_logo",
            "created_at",
            "closed_at",
        ]] for row in opportunities],
    )
    write(
        "marketing_spend.csv",
        ["channel", "channel_name", "spend", "sort_order"],
        [[row["id"], row["name"], row["spend"], row["sort"]] for row in cfg["channels"]],
    )
    write(
        "goals.csv",
        ["goal_id", "label", "detail", "unit", "metric_kind", "target_value", "sort_order"],
        [
            [row["id"], row["label"], row["detail"], row["unit"], row["kind"], row["target"], row["sort"]]
            for row in cfg["goals"]
        ],
    )
    write(
        "quarter.csv",
        [
            "quarter_start",
            "quarter_end",
            "funnel_start",
            "win_rate_start",
            "chart_start",
            "on_track_ratio",
            "at_risk_ratio",
            "renewal_horizon_days",
            "trend_points",
        ],
        [[
            cfg["quarter_start"],
            cfg["quarter_end"],
            cfg["funnel_start"],
            cfg["win_rate_start"],
            cfg["chart_start"],
            cfg["on_track_ratio"],
            cfg["at_risk_ratio"],
            cfg["renewal_horizon_days"],
            cfg["trend_points"],
        ]],
    )


def build_commercial(raw_dir: Path) -> dict:
    cfg = load_commercial()
    opportunities = build_opportunities(cfg)
    customers, sites, radiologists, studies = build_usage(cfg)
    write_commercial_tables(raw_dir, cfg, opportunities)
    print(
        f"Commercial rows: {len(opportunities)} opportunities, {len(studies)} account studies."
    )
    return {
        "customers": customers,
        "sites": sites,
        "radiologists": radiologists,
        "studies": studies,
    }
