#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUMMARY="$ROOT_DIR/results/summary.csv"
export ROOT_DIR

if [ ! -f "$SUMMARY" ]; then
  echo "summary.csv not found. Run stage1 first." >&2
  exit 1
fi

read -r STABLE_N MARGINAL_N < <(
  python3 - <<'PY'
import csv
import os
from collections import defaultdict

root_dir = os.environ.get("ROOT_DIR", ".")
summary_path = os.path.join(root_dir, "results", "summary.csv")
N_LIST = [5, 10, 15, 20, 25, 30, 40, 50]

rows = []
with open(summary_path, newline="", encoding="utf-8") as handle:
    reader = csv.DictReader(handle)
    rows = [r for r in reader if r.get("stage") == "stage1" and r.get("mode") == "rpl-lite"]

pdr_by_n = defaultdict(list)
for row in rows:
    try:
        n = int(row["n_senders"])
        pdr = float(row["pdr"])
    except (ValueError, KeyError):
        continue
    pdr_by_n[n].append(pdr)

avg_pdr = {n: (sum(vals) / len(vals)) for n, vals in pdr_by_n.items() if vals}

stable_candidates = [n for n in N_LIST if avg_pdr.get(n, 0.0) >= 0.95]
marginal_candidates = [n for n in N_LIST if 0.90 <= avg_pdr.get(n, 0.0) < 0.95]

stable_n = max(stable_candidates) if stable_candidates else N_LIST[0]
if marginal_candidates:
    marginal_n = max(marginal_candidates)
else:
    try:
        stable_idx = N_LIST.index(stable_n)
        marginal_n = N_LIST[min(stable_idx + 1, len(N_LIST) - 1)]
    except ValueError:
        marginal_n = stable_n

print(f"{stable_n} {marginal_n}")
PY
)

STAGE="stage2"
MODE_LIST=("rpl-lite" "brpl")
N_LIST=()
if [ "$STABLE_N" -eq "$MARGINAL_N" ]; then
  N_LIST=("$STABLE_N")
else
  N_LIST=("$STABLE_N" "$MARGINAL_N")
fi

SUCCESS_LIST=(1.0 0.95 0.9 0.85 0.8 0.75)
INTERFERENCE_LIST=(1.0 0.95 0.9 0.85)
SEEDS=(1 2 3)
SEND_INTERVAL_S="${SEND_INTERVAL_S:-10}"

total=$(( ${#MODE_LIST[@]} * ${#N_LIST[@]} * ${#SUCCESS_LIST[@]} * ${#INTERFERENCE_LIST[@]} * ${#SEEDS[@]} ))
count=0
export SKIP_THRESHOLDS=1

for mode in "${MODE_LIST[@]}"; do
  for n in "${N_LIST[@]}"; do
    for success in "${SUCCESS_LIST[@]}"; do
      for interference in "${INTERFERENCE_LIST[@]}"; do
        for seed in "${SEEDS[@]}"; do
          count=$((count + 1))
          printf "[stage2 %s/%s] mode=%s n=%s seed=%s sr=%s ir=%s si=%s @ %s\n" \
            "$count" "$total" "$mode" "$n" "$seed" "$success" "$interference" "$SEND_INTERVAL_S" "$(date '+%F %T')"
          "$ROOT_DIR/scripts/run_experiment.sh" \
            --mode "$mode" \
            --stage "$STAGE" \
            --n-senders "$n" \
            --seed "$seed" \
            --success-ratio "$success" \
            --interference-ratio "$interference" \
            --send-interval "$SEND_INTERVAL_S" || true
        done
      done
    done
  done
 done

Rscript "$ROOT_DIR/tools/R/find_thresholds.R" \
  --summary "$ROOT_DIR/results/summary.csv" \
  --out "$ROOT_DIR/results/thresholds.csv" || true

printf "Stage2 sweep complete. Summary: %s/results/summary.csv\n" "$ROOT_DIR"
