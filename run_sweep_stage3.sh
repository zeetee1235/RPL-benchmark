#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUMMARY="$ROOT_DIR/results/summary.csv"

if [ ! -f "$SUMMARY" ]; then
  echo "summary.csv not found. Run stage2 first." >&2
  exit 1
fi

read -r SELECTED_N SELECTED_SUCCESS SELECTED_INTERFERENCE < <(
  python3 - <<'PY'
import csv
from collections import defaultdict

summary_path = "results/summary.csv"

rows = []
with open(summary_path, newline="", encoding="utf-8") as handle:
    reader = csv.DictReader(handle)
    rows = [r for r in reader if r.get("stage") == "stage2" and r.get("mode") == "rpl-classic"]

cond_map = defaultdict(list)
for row in rows:
    try:
        n = int(row["n_senders"])
        success = float(row["success_ratio"])
        interference = float(row["interference_ratio"])
        pdr = float(row["pdr"])
    except (ValueError, KeyError):
        continue
    cond_map[(n, success, interference)].append(pdr)

if not cond_map:
    print("0 1.0 1.0")
    raise SystemExit(0)

avg_pdr = {k: sum(v) / len(v) for k, v in cond_map.items()}

in_range = {k: v for k, v in avg_pdr.items() if 0.85 <= v <= 0.92}
if in_range:
    selected = min(in_range.items(), key=lambda kv: abs(kv[1] - 0.90))[0]
else:
    selected = min(avg_pdr.items(), key=lambda kv: abs(kv[1] - 0.90))[0]

n, success, interference = selected
print(f"{n} {success} {interference}")
PY
)

STAGE="stage3"
MODE_LIST=("rpl-classic" "brpl")
SEEDS=(1 2 3)
SEND_INTERVAL_LIST=(20 10 5 2)

for mode in "${MODE_LIST[@]}"; do
  for interval in "${SEND_INTERVAL_LIST[@]}"; do
    for seed in "${SEEDS[@]}"; do
      "$ROOT_DIR/run_experiment.sh" \
        --mode "$mode" \
        --stage "$STAGE" \
        --n-senders "$SELECTED_N" \
        --seed "$seed" \
        --success-ratio "$SELECTED_SUCCESS" \
        --interference-ratio "$SELECTED_INTERFERENCE" \
        --send-interval "$interval" || true
    done
  done
 done

python3 "$ROOT_DIR/tools/python/find_thresholds.py" \
  --summary "$ROOT_DIR/results/summary.csv" \
  --out "$ROOT_DIR/results/thresholds.csv" || true

printf "Stage3 sweep complete. Summary: %s/results/summary.csv\n" "$ROOT_DIR"
