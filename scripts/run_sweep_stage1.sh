#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

STAGE="stage1"
MODE_LIST=("rpl-classic" "brpl")
N_LIST=(5 10 15 20 25 30 40 50)
SEEDS=(1 2 3)

SUCCESS_RATIO="${SUCCESS_RATIO:-1.0}"
INTERFERENCE_RATIO="${INTERFERENCE_RATIO:-1.0}"
SEND_INTERVAL_S="${SEND_INTERVAL_S:-10}"

total=$(( ${#MODE_LIST[@]} * ${#N_LIST[@]} * ${#SEEDS[@]} ))
count=0

for mode in "${MODE_LIST[@]}"; do
  make -C "$ROOT_DIR" TARGET=cooja clean
  for n in "${N_LIST[@]}"; do
    for seed in "${SEEDS[@]}"; do
      count=$((count + 1))
      printf "[stage1 %s/%s] mode=%s n=%s seed=%s sr=%s ir=%s si=%s @ %s\n" \
        "$count" "$total" "$mode" "$n" "$seed" "$SUCCESS_RATIO" "$INTERFERENCE_RATIO" "$SEND_INTERVAL_S" "$(date '+%F %T')"
      "$ROOT_DIR/scripts/run_experiment.sh" \
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

Rscript "$ROOT_DIR/tools/R/find_thresholds.R" \
  --summary "$ROOT_DIR/results/summary.csv" \
  --out "$ROOT_DIR/results/thresholds.csv" || true

printf "Stage1 sweep complete. Summary: %s/results/summary.csv\n" "$ROOT_DIR"
