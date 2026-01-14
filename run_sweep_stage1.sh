#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

STAGE="stage1"
MODE_LIST=("rpl-classic" "brpl")
N_LIST=(5 10 15 20 25 30 40 50)
SEEDS=(1 2 3)

SUCCESS_RATIO="${SUCCESS_RATIO:-1.0}"
INTERFERENCE_RATIO="${INTERFERENCE_RATIO:-1.0}"
SEND_INTERVAL_S="${SEND_INTERVAL_S:-10}"

for mode in "${MODE_LIST[@]}"; do
  for n in "${N_LIST[@]}"; do
    for seed in "${SEEDS[@]}"; do
      "$ROOT_DIR/run_experiment.sh" \
        --mode "$mode" \
        --stage "$STAGE" \
        --n-senders "$n" \
        --seed "$seed" \
        --success-ratio "$SUCCESS_RATIO" \
        --interference-ratio "$INTERFERENCE_RATIO" \
        --send-interval "$SEND_INTERVAL_S" || true
    done
  done
 done

python3 "$ROOT_DIR/tools/python/find_thresholds.py" \
  --summary "$ROOT_DIR/results/summary.csv" \
  --out "$ROOT_DIR/results/thresholds.csv" || true

printf "Stage1 sweep complete. Summary: %s/results/summary.csv\n" "$ROOT_DIR"
