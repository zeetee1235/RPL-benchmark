#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTIKI="${CONTIKI:-$ROOT_DIR/../external/contiki-ng}"
COOJA_JAR="$CONTIKI/tools/cooja/dist/cooja.jar"
RESULTS_DIR="$ROOT_DIR/results"

MODE="${MODE:-rpl-classic}"
STAGE="${STAGE:-stage1}"
N_SENDERS="${N_SENDERS:-5}"
SEED="${SEED:-1}"
SUCCESS_RATIO="${SUCCESS_RATIO:-1.0}"
INTERFERENCE_RATIO="${INTERFERENCE_RATIO:-1.0}"
TX_RANGE="${TX_RANGE:-60}"
INT_RANGE="${INT_RANGE:-100}"
SEND_INTERVAL_S="${SEND_INTERVAL_S:-10}"
DURATION_S="${DURATION_S:-360}"
WARMUP_S="${WARMUP_S:-60}"
MEASURE_S="${MEASURE_S:-300}"
SIM_TIMEOUT_S="${SIM_TIMEOUT_S:-600}"
CLOCK_SECOND="${CLOCK_SECOND:-128}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"; shift 2 ;;
    --stage)
      STAGE="$2"; shift 2 ;;
    --n-senders)
      N_SENDERS="$2"; shift 2 ;;
    --seed)
      SEED="$2"; shift 2 ;;
    --success-ratio)
      SUCCESS_RATIO="$2"; shift 2 ;;
    --interference-ratio)
      INTERFERENCE_RATIO="$2"; shift 2 ;;
    --send-interval)
      SEND_INTERVAL_S="$2"; shift 2 ;;
    --tx-range)
      TX_RANGE="$2"; shift 2 ;;
    --int-range)
      INT_RANGE="$2"; shift 2 ;;
    --duration-s)
      DURATION_S="$2"; shift 2 ;;
    --warmup-s)
      WARMUP_S="$2"; shift 2 ;;
    --measure-s)
      MEASURE_S="$2"; shift 2 ;;
    --timeout-s)
      SIM_TIMEOUT_S="$2"; shift 2 ;;
    --clock-second)
      CLOCK_SECOND="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
 done

if [ ! -d "$CONTIKI" ]; then
  echo "CONTIKI not found at $CONTIKI" >&2
  echo "Set CONTIKI env var to your contiki-ng path." >&2
  exit 1
fi

if [ ! -f "$COOJA_JAR" ]; then
  echo "Cooja jar not found: $COOJA_JAR" >&2
  echo "Build it with: (cd $CONTIKI/tools/cooja && ./gradlew jar)" >&2
  exit 1
fi

case "$MODE" in
  rpl-classic)
    MAKE_ROUTING="MAKE_ROUTING_RPL_CLASSIC"
    BRPL_FLAG=""
    ;;
  brpl)
    MAKE_ROUTING="MAKE_ROUTING_RPL_LITE"
    BRPL_FLAG="BRPL_MODE=1"
    ;;
  rpl-lite)
    MAKE_ROUTING="MAKE_ROUTING_RPL_LITE"
    BRPL_FLAG=""
    ;;
  *)
    echo "Unknown mode: $MODE (use rpl-classic, brpl, or rpl-lite)" >&2
    exit 2
    ;;
 esac

sanitize() {
  local value="$1"
  value="${value//./p}"
  echo "$value"
}

SUCCESS_TAG="$(sanitize "$SUCCESS_RATIO")"
INTERFERENCE_TAG="$(sanitize "$INTERFERENCE_RATIO")"
INTERVAL_TAG="$(sanitize "$SEND_INTERVAL_S")"

RAW_DIR="$RESULTS_DIR/raw/$STAGE/$MODE"
mkdir -p "$RAW_DIR"

BASENAME="N${N_SENDERS}_seed${SEED}_sr${SUCCESS_TAG}_ir${INTERFERENCE_TAG}_si${INTERVAL_TAG}"
CSC_PATH="$RAW_DIR/${BASENAME}.csc"
LOG_PATH="$RAW_DIR/${BASENAME}.log"
CSV_PATH="$RAW_DIR/${BASENAME}.csv"
SUMMARY_PATH="$RESULTS_DIR/summary.csv"

SIM_TIME_MS=$((DURATION_S * 1000))

DEFINES="SEND_INTERVAL_SECONDS=$SEND_INTERVAL_S"
if [ -n "$BRPL_FLAG" ]; then
  DEFINES="$DEFINES $BRPL_FLAG"
fi

make -C "$ROOT_DIR" TARGET=cooja receiver_root.cooja sender.cooja \
  MAKE_ROUTING="$MAKE_ROUTING" DEFINES="$DEFINES"

python3 "$ROOT_DIR/tools/gen_csc.py" \
  --root-dir "$ROOT_DIR" \
  --senders "$N_SENDERS" \
  --seed "$SEED" \
  --make-routing "$MAKE_ROUTING" \
  --send-interval "$SEND_INTERVAL_S" \
  ${BRPL_FLAG:+--brpl} \
  --sim-time-ms "$SIM_TIME_MS" \
  --tx-range "$TX_RANGE" \
  --int-range "$INT_RANGE" \
  --success-tx "$SUCCESS_RATIO" \
  --success-rx "$INTERFERENCE_RATIO" \
  --out "$CSC_PATH"

set +e
if command -v timeout >/dev/null 2>&1; then
  timeout "$SIM_TIMEOUT_S" java --enable-preview -jar "$COOJA_JAR" -nogui="$CSC_PATH" > "$LOG_PATH" 2>&1
  COOJA_STATUS=$?
else
  java --enable-preview -jar "$COOJA_JAR" -nogui="$CSC_PATH" > "$LOG_PATH" 2>&1
  COOJA_STATUS=$?
fi
set -e

if [ $COOJA_STATUS -ne 0 ]; then
  echo "Cooja run failed (status $COOJA_STATUS) for $BASENAME" >&2
fi

if rg '^CSV,' "$LOG_PATH" > "$CSV_PATH"; then
  :
else
  echo "" > "$CSV_PATH"
fi

python3 "$ROOT_DIR/tools/python/log_parser.py" \
  --csv "$CSV_PATH" \
  --cooja-log "$LOG_PATH" \
  --mode "$MODE" \
  --stage "$STAGE" \
  --n-senders "$N_SENDERS" \
  --seed "$SEED" \
  --success-ratio "$SUCCESS_RATIO" \
  --interference-ratio "$INTERFERENCE_RATIO" \
  --send-interval-s "$SEND_INTERVAL_S" \
  --duration-s "$DURATION_S" \
  --warmup-s "$WARMUP_S" \
  --measure-s "$MEASURE_S" \
  --clock-second "$CLOCK_SECOND" \
  --log-path "$LOG_PATH" \
  --csc-path "$CSC_PATH" \
  --out "$SUMMARY_PATH"

python3 "$ROOT_DIR/tools/python/find_thresholds.py" \
  --summary "$SUMMARY_PATH" \
  --out "$RESULTS_DIR/thresholds.csv" || true

if [ $COOJA_STATUS -ne 0 ]; then
  exit 0
fi

printf "Completed %s %s seed=%s (summary: %s)\n" "$MODE" "$BASENAME" "$SEED" "$SUMMARY_PATH"
