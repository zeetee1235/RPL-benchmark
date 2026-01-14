#!/usr/bin/env python3
"""Parse rpl-benchmark CSV logs and append a summary row."""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path


def parse_log(path: Path) -> dict:
    stats = defaultdict(lambda: {"rx": 0, "gap": 0, "delay_sum": 0, "delay_cnt": 0})

    for line in path.read_text(errors="ignore").splitlines():
        if not line.startswith("CSV,RX,"):
            continue
        parts = line.strip().split(",")
        if len(parts) < 10:
            continue
        _, _, src_ip, _, seq, _t_send, _t_recv, delay_ticks, _len, gap = parts[:10]
        if seq == "NA":
            continue
        st = stats[src_ip]
        st["rx"] += 1
        st["gap"] += int(gap)
        st["delay_sum"] += int(delay_ticks)
        st["delay_cnt"] += 1

    total_rx = 0
    total_expected = 0
    total_delay_sum = 0
    total_delay_cnt = 0

    for st in stats.values():
        expected = st["rx"] + st["gap"]
        total_rx += st["rx"]
        total_expected += expected
        total_delay_sum += st["delay_sum"]
        total_delay_cnt += st["delay_cnt"]

    pdr = (total_rx / total_expected) if total_expected else 0.0
    avg_delay = (total_delay_sum / total_delay_cnt) if total_delay_cnt else 0.0

    return {
        "rx": total_rx,
        "expected": total_expected,
        "pdr": pdr,
        "avg_delay_ticks": avg_delay,
        "senders_seen": len(stats),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse RX CSV logs and summarize")
    parser.add_argument("--log", required=True, help="Cooja log file path")
    parser.add_argument("--mode", required=True, help="Experiment mode label")
    parser.add_argument("--senders", type=int, required=True, help="Configured sender count")
    parser.add_argument("--send-interval", type=int, required=True, help="Sender interval seconds")
    parser.add_argument("--sim-time-ms", type=int, required=True, help="Simulation time ms")
    parser.add_argument("--tx-range", required=True, help="UDGM transmit range")
    parser.add_argument("--success-tx", required=True, help="UDGM success_ratio_tx")
    parser.add_argument("--success-rx", required=True, help="UDGM success_ratio_rx")
    parser.add_argument("--out", required=True, help="Output summary CSV path")
    args = parser.parse_args()

    log_path = Path(args.log)
    summary = parse_log(log_path)

    out_path = Path(args.out)
    header = (
        "mode,senders,senders_seen,send_interval,sim_time_ms,"
        "tx_range,success_tx,success_rx,rx,expected,pdr,avg_delay_ticks,log_file\n"
    )
    row = (
        f"{args.mode},{args.senders},{summary['senders_seen']},{args.send_interval},"
        f"{args.sim_time_ms},{args.tx_range},{args.success_tx},{args.success_rx},"
        f"{summary['rx']},{summary['expected']},{summary['pdr']:.6f},{summary['avg_delay_ticks']:.2f},"
        f"{log_path}\n"
    )

    if not out_path.exists():
        out_path.write_text(header + row)
    else:
        with out_path.open("a", encoding="utf-8") as f:
            f.write(row)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
