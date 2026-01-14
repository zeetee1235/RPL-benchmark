#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODE_LIST=("rpl-lite" "rpl-classic" "brpl")
SENDER_LIST=(10 20 30 40 50 60)

# Stress settings to push RPL toward instability.
export SEND_INTERVAL=10
export SIM_TIME_MS=600000
export TX_RANGE=45
export INT_RANGE=90
export SUCCESS_TX=0.9
export SUCCESS_RX=0.7

for mode in "${MODE_LIST[@]}"; do
  for n in "${SENDER_LIST[@]}"; do
    "$ROOT_DIR/run_experiment.sh" "$mode" "$n"
  done
done

echo "Sweep complete. Summary: $ROOT_DIR/logs/summary.csv"
