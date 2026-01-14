#!/usr/bin/env python3
"""Find collapse thresholds per mode/stage from summary.csv."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from statistics import mean


@dataclass(frozen=True)
class Condition:
    mode: str
    stage: str
    n_senders: int
    success_ratio: float
    interference_ratio: float
    send_interval_s: int


@dataclass
class Aggregate:
    pdr: float
    avg_delay_ms: float
    overhead: float


def parse_float(value: str) -> float:
    try:
        return float(value)
    except ValueError:
        return 0.0


def parse_int(value: str) -> int:
    try:
        return int(value)
    except ValueError:
        return 0


def condition_key(row: dict) -> Condition:
    return Condition(
        mode=row["mode"],
        stage=row["stage"],
        n_senders=parse_int(row["n_senders"]),
        success_ratio=parse_float(row["success_ratio"]),
        interference_ratio=parse_float(row["interference_ratio"]),
        send_interval_s=parse_int(row["send_interval_s"]),
    )


def condition_label(cond: Condition) -> str:
    if cond.stage == "stage1":
        return f"N={cond.n_senders}"
    if cond.stage == "stage2":
        return (
            f"N={cond.n_senders}, success_ratio={cond.success_ratio}, "
            f"interference_ratio={cond.interference_ratio}"
        )
    return (
        f"N={cond.n_senders}, success_ratio={cond.success_ratio}, "
        f"interference_ratio={cond.interference_ratio}, "
        f"send_interval_s={cond.send_interval_s}"
    )


def sort_key(cond: Condition) -> tuple:
    if cond.stage == "stage1":
        return (cond.n_senders,)
    if cond.stage == "stage2":
        return (-cond.success_ratio, -cond.interference_ratio, cond.n_senders)
    return (-cond.send_interval_s, cond.n_senders, -cond.success_ratio, -cond.interference_ratio)


def main() -> int:
    parser = argparse.ArgumentParser(description="Find collapse thresholds per mode")
    parser.add_argument("--summary", required=True, help="summary.csv path")
    parser.add_argument("--out", required=True, help="thresholds.csv output path")
    args = parser.parse_args()

    summary_path = Path(args.summary)
    if not summary_path.exists():
        raise SystemExit("summary.csv not found")

    rows: list[dict] = []
    with summary_path.open("r", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)

    grouped: dict[Condition, list[dict]] = defaultdict(list)
    for row in rows:
        cond = condition_key(row)
        grouped[cond].append(row)

    aggregates: dict[Condition, Aggregate] = {}
    for cond, group_rows in grouped.items():
        pdr_values = [parse_float(r.get("pdr", "0")) for r in group_rows]
        delay_values = [parse_float(r.get("avg_delay_ms", "0")) for r in group_rows]
        overhead_values = [
            parse_int(r.get("dio_count", "0")) + parse_int(r.get("dao_count", "0"))
            for r in group_rows
        ]
        aggregates[cond] = Aggregate(
            pdr=mean(pdr_values) if pdr_values else 0.0,
            avg_delay_ms=mean(delay_values) if delay_values else 0.0,
            overhead=mean(overhead_values) if overhead_values else 0.0,
        )

    thresholds: list[dict] = []
    modes = sorted({cond.mode for cond in aggregates})
    stages = ["stage1", "stage2", "stage3"]

    for mode in modes:
        for stage in stages:
            stage_conditions = [
                cond
                for cond in aggregates
                if cond.mode == mode and cond.stage == stage
            ]
            if not stage_conditions:
                continue
            stage_conditions.sort(key=sort_key)

            prev_overhead = None
            threshold_row = None
            for cond in stage_conditions:
                agg = aggregates[cond]
                overhead_spike = False
                if prev_overhead is not None and prev_overhead > 0 and agg.overhead > 0:
                    overhead_spike = agg.overhead >= (2 * prev_overhead)
                is_collapse = agg.pdr < 0.90 or agg.avg_delay_ms > 5000 or overhead_spike
                notes = []
                if agg.pdr < 0.90:
                    notes.append("pdr<0.90")
                if agg.avg_delay_ms > 5000:
                    notes.append("delay>5000ms")
                if overhead_spike:
                    notes.append("control_overhead_spike")
                if is_collapse and threshold_row is None:
                    threshold_row = {
                        "mode": mode,
                        "stage": stage,
                        "threshold_condition_string": condition_label(cond),
                        "pdr": f"{agg.pdr:.6f}",
                        "avg_delay_ms": f"{agg.avg_delay_ms:.2f}",
                        "overhead": f"{agg.overhead:.2f}",
                        "notes": ";".join(notes) if notes else "collapse",
                    }
                    break
                prev_overhead = agg.overhead

            if threshold_row is None:
                first_cond = stage_conditions[-1]
                agg = aggregates[first_cond]
                threshold_row = {
                    "mode": mode,
                    "stage": stage,
                    "threshold_condition_string": "none",
                    "pdr": f"{agg.pdr:.6f}",
                    "avg_delay_ms": f"{agg.avg_delay_ms:.2f}",
                    "overhead": f"{agg.overhead:.2f}",
                    "notes": "no collapse found",
                }
            thresholds.append(threshold_row)

    out_path = Path(args.out)
    header = "mode,stage,threshold_condition_string,pdr,avg_delay_ms,overhead,notes\n"
    with out_path.open("w", encoding="utf-8") as handle:
        handle.write(header)
        for row in thresholds:
            handle.write(
                f"{row['mode']},{row['stage']},{row['threshold_condition_string']},"
                f"{row['pdr']},{row['avg_delay_ms']},{row['overhead']},{row['notes']}\n"
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
