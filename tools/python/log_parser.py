#!/usr/bin/env python3
"""Parse raw RX CSV logs and append a per-run summary row."""

from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path
from statistics import mean


def parse_rx_csv(
    path: Path,
    warmup_s: float,
    measure_s: float,
    clock_second: int,
) -> dict:
    stats = {}
    delays_ms: list[float] = []
    rx_total = 0
    gap_total = 0

    if not path.exists():
        return {
            "rx": 0,
            "expected": 0,
            "pdr": 0.0,
            "avg_delay_ms": 0.0,
            "p95_delay_ms": 0.0,
        }

    with path.open("r", encoding="utf-8", errors="ignore") as handle:
        reader = csv.reader(handle)
        for row in reader:
            if len(row) < 10:
                continue
            if row[0] != "CSV" or row[1] != "RX":
                continue
            _, _, src_ip, _src_port, seq, _t_send, t_recv, delay_ticks, _length, gap = row[:10]
            if seq == "NA":
                continue
            try:
                t_recv_ticks = int(t_recv)
                delay_ticks_int = int(delay_ticks)
                gap_int = int(gap)
            except ValueError:
                continue
            t_recv_s = t_recv_ticks / clock_second
            if t_recv_s < warmup_s or t_recv_s >= warmup_s + measure_s:
                continue

            sender = stats.setdefault(src_ip, {"rx": 0, "gap": 0})
            sender["rx"] += 1
            sender["gap"] += gap_int

            rx_total += 1
            gap_total += gap_int
            delays_ms.append((delay_ticks_int * 1000.0) / clock_second)

    expected = rx_total + gap_total
    pdr = (rx_total / expected) if expected else 0.0
    avg_delay_ms = mean(delays_ms) if delays_ms else 0.0
    if delays_ms:
        delays_sorted = sorted(delays_ms)
        p95_index = max(0, math.ceil(0.95 * len(delays_sorted)) - 1)
        p95_delay_ms = delays_sorted[p95_index]
    else:
        p95_delay_ms = 0.0

    return {
        "rx": rx_total,
        "expected": expected,
        "pdr": pdr,
        "avg_delay_ms": avg_delay_ms,
        "p95_delay_ms": p95_delay_ms,
    }


def count_control_messages(log_path: Path) -> tuple[int, int]:
    if not log_path.exists():
        return 0, 0
    text = log_path.read_text(errors="ignore")
    dio_count = len(re.findall(r"\bDIO\b", text))
    dao_count = len(re.findall(r"\bDAO\b", text))
    return dio_count, dao_count


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse RX CSV logs and summarize")
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
    summary = parse_rx_csv(csv_path, args.warmup_s, args.measure_s, args.clock_second)

    dio_count = 0
    dao_count = 0
    if args.cooja_log:
        dio_count, dao_count = count_control_messages(Path(args.cooja_log))

    out_path = Path(args.out)
    header = (
        "mode,stage,n_senders,seed,success_ratio,interference_ratio,send_interval_s,"
        "rx_count,tx_expected,pdr,avg_delay_ms,p95_delay_ms,dio_count,dao_count,"
        "duration_s,warmup_s,measure_s,log_path,csc_path\n"
    )
    row = (
        f"{args.mode},{args.stage},{args.n_senders},{args.seed},"
        f"{args.success_ratio},{args.interference_ratio},{args.send_interval_s},"
        f"{summary['rx']},{summary['expected']},{summary['pdr']:.6f},"
        f"{summary['avg_delay_ms']:.2f},{summary['p95_delay_ms']:.2f},"
        f"{dio_count},{dao_count},{args.duration_s},{args.warmup_s},{args.measure_s},"
        f"{args.log_path},{args.csc_path}\n"
    )

    if not out_path.exists():
        out_path.write_text(header + row)
    else:
        with out_path.open("a", encoding="utf-8") as handle:
            handle.write(row)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
