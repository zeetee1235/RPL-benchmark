#!/usr/bin/env python3
"""Parse RTT/RX CSV logs and write a per-run summary row."""

from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path
from statistics import mean


def parse_csv(
    path: Path,
    warmup_s: float,
    measure_s: float,
    clock_second: int,
) -> dict:
    rtt_ms: list[float] = []
    rtt_ticks: list[int] = []
    rx_total = 0
    gap_total = 0
    last_seq_by_src: dict[str, int] = {}

    if not path.exists():
        return {
            "rx": 0,
            "expected": 0,
            "pdr": 0.0,
            "avg_rtt_ms": 0.0,
            "p95_rtt_ms": 0.0,
            "invalid_run": 1,
        }

    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        reader = csv.reader(handle)
        for row in reader:
            if len(row) < 2:
                continue
            if row[0] != "CSV":
                continue
            tag = row[1]
            if tag == "RTT" and len(row) >= 7:
                _, _, seq, _t0, t_ack, rtt_ticks_str, _length = row[:7]
                try:
                    t_ack_ticks = int(t_ack)
                    rtt_ticks_int = int(rtt_ticks_str)
                except ValueError:
                    continue
                t_ack_s = t_ack_ticks / clock_second
                if t_ack_s < warmup_s or t_ack_s >= warmup_s + measure_s:
                    continue
                rtt_ticks.append(rtt_ticks_int)
                rtt_ms.append((rtt_ticks_int * 1000.0) / clock_second)
            elif tag == "RX" and len(row) >= 6:
                _, _, src_ip, seq, t_recv, _length = row[:6]
                if seq == "NA":
                    continue
                try:
                    seq_int = int(seq)
                    t_recv_ticks = int(t_recv)
                except ValueError:
                    continue
                t_recv_s = t_recv_ticks / clock_second
                if t_recv_s < warmup_s or t_recv_s >= warmup_s + measure_s:
                    continue
                last_seq = last_seq_by_src.get(src_ip)
                if last_seq is not None and seq_int > last_seq + 1:
                    gap_total += seq_int - (last_seq + 1)
                last_seq_by_src[src_ip] = seq_int
                rx_total += 1

    expected = rx_total + gap_total
    pdr = (rx_total / expected) if expected else 0.0
    avg_rtt_ms = mean(rtt_ms) if rtt_ms else 0.0
    if rtt_ms:
        rtt_sorted = sorted(rtt_ms)
        p95_index = max(0, math.ceil(0.95 * len(rtt_sorted)) - 1)
        p95_rtt_ms = rtt_sorted[p95_index]
    else:
        p95_rtt_ms = 0.0

    invalid_run = 0
    if not rtt_ms or all(t == 0 for t in rtt_ticks):
        invalid_run = 1

    return {
        "rx": rx_total,
        "expected": expected,
        "pdr": pdr,
        "avg_rtt_ms": avg_rtt_ms,
        "p95_rtt_ms": p95_rtt_ms,
        "invalid_run": invalid_run,
    }


def count_control_messages(log_path: Path) -> tuple[int, int]:
    if not log_path.exists():
        return 0, 0
    text = log_path.read_text(errors="ignore")
    dio_count = len(re.findall(r"\bDIO\b", text))
    dao_count = len(re.findall(r"\bDAO\b", text))
    return dio_count, dao_count


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse RTT/RX CSV logs and summarize")
    parser.add_argument("--csv", required=True, help="Raw RX CSV path")
    parser.add_argument("--cooja-log", required=False, help="Full Cooja log path")
    parser.add_argument("--mode", required=True, help="Experiment mode label")
    parser.add_argument("--stage", required=True, help="Stage label")
    parser.add_argument("--n-senders", type=int, required=True, help="Configured sender count")
    parser.add_argument("--seed", type=int, required=True, help="Random seed")
    parser.add_argument("--success-ratio", type=float, required=True, help="UDGM success_ratio_tx/rx")
    parser.add_argument("--interference-ratio", type=float, required=True, help="UDGM interference ratio")
    parser.add_argument("--send-interval-s", type=int, required=True, help="Sender interval seconds")
    parser.add_argument("--duration-s", type=int, required=True, help="Simulation duration seconds")
    parser.add_argument("--warmup-s", type=int, required=True, help="Warmup seconds")
    parser.add_argument("--measure-s", type=int, required=True, help="Measure seconds")
    parser.add_argument("--clock-second", type=int, default=128, help="Contiki clock ticks per second")
    parser.add_argument("--log-path", required=True, help="Log file path")
    parser.add_argument("--csc-path", required=True, help="Cooja CSC path")
    parser.add_argument("--out", required=True, help="Output summary CSV path")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    summary = parse_csv(csv_path, args.warmup_s, args.measure_s, args.clock_second)

    dio_count = 0
    dao_count = 0
    if args.cooja_log:
        dio_count, dao_count = count_control_messages(Path(args.cooja_log))

    out_path = Path(args.out)
    header = [
        "mode",
        "stage",
        "n_senders",
        "seed",
        "success_ratio",
        "interference_ratio",
        "send_interval_s",
        "rx_count",
        "tx_expected",
        "pdr",
        "avg_rtt_ms",
        "p95_rtt_ms",
        "avg_delay_ms",
        "p95_delay_ms",
        "invalid_run",
        "dio_count",
        "dao_count",
        "duration_s",
        "warmup_s",
        "measure_s",
        "log_path",
        "csc_path",
    ]

    row = {
        "mode": args.mode,
        "stage": args.stage,
        "n_senders": str(args.n_senders),
        "seed": str(args.seed),
        "success_ratio": str(args.success_ratio),
        "interference_ratio": str(args.interference_ratio),
        "send_interval_s": str(args.send_interval_s),
        "rx_count": str(summary["rx"]),
        "tx_expected": str(summary["expected"]),
        "pdr": f"{summary['pdr']:.6f}",
        "avg_rtt_ms": f"{summary['avg_rtt_ms']:.2f}",
        "p95_rtt_ms": f"{summary['p95_rtt_ms']:.2f}",
        "avg_delay_ms": f"{summary['avg_rtt_ms']:.2f}",
        "p95_delay_ms": f"{summary['p95_rtt_ms']:.2f}",
        "invalid_run": str(summary["invalid_run"]),
        "dio_count": str(dio_count),
        "dao_count": str(dao_count),
        "duration_s": str(args.duration_s),
        "warmup_s": str(args.warmup_s),
        "measure_s": str(args.measure_s),
        "log_path": str(args.log_path),
        "csc_path": str(args.csc_path),
    }

    key = (
        row["mode"],
        row["stage"],
        row["n_senders"],
        row["seed"],
        row["success_ratio"],
        row["interference_ratio"],
        row["send_interval_s"],
    )

    rows_by_key: dict[tuple[str, ...], dict[str, str]] = {}
    if out_path.exists():
        with out_path.open("r", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            for existing in reader:
                existing_key = (
                    existing.get("mode", ""),
                    existing.get("stage", ""),
                    existing.get("n_senders", ""),
                    existing.get("seed", ""),
                    existing.get("success_ratio", ""),
                    existing.get("interference_ratio", ""),
                    existing.get("send_interval_s", ""),
                )
                rows_by_key[existing_key] = existing

    rows_by_key[key] = row
    with out_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=header)
        writer.writeheader()
        for key in sorted(rows_by_key):
            existing = rows_by_key[key]
            normalized = {name: existing.get(name, "") for name in header}
            writer.writerow(normalized)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
