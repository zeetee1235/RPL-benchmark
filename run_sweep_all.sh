#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[all] Stage 1 start @ $(date '+%F %T')"
"$ROOT_DIR/run_sweep_stage1.sh"
echo "[all] Stage 1 done @ $(date '+%F %T')"

echo "[all] Stage 2 start @ $(date '+%F %T')"
"$ROOT_DIR/run_sweep_stage2.sh"
echo "[all] Stage 2 done @ $(date '+%F %T')"

echo "[all] Stage 3 start @ $(date '+%F %T')"
"$ROOT_DIR/run_sweep_stage3.sh"
echo "[all] Stage 3 done @ $(date '+%F %T')"
