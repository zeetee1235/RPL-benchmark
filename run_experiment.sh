#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTIKI="${CONTIKI:-$ROOT_DIR/../external/contiki-ng}"
COOJA_JAR="$CONTIKI/tools/cooja/dist/cooja.jar"
CSC_OUT="$ROOT_DIR/cooja/brpl_stress.csc"
LOG_DIR="$ROOT_DIR/logs"

MODE="${1:-rpl-lite}"
SENDERS="${2:-3}"

SEND_INTERVAL="${SEND_INTERVAL:-10}"
SIM_TIME_MS="${SIM_TIME_MS:-600000}"
TX_RANGE="${TX_RANGE:-60}"
INT_RANGE="${INT_RANGE:-100}"
SUCCESS_TX="${SUCCESS_TX:-1.0}"
SUCCESS_RX="${SUCCESS_RX:-1.0}"

mkdir -p "$LOG_DIR"

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
  rpl-lite)
    MAKE_ROUTING="MAKE_ROUTING_RPL_LITE"
    BRPL_FLAG=""
    ;;
  rpl-classic)
    MAKE_ROUTING="MAKE_ROUTING_RPL_CLASSIC"
    BRPL_FLAG=""
    ;;
  brpl)
    MAKE_ROUTING="MAKE_ROUTING_RPL_LITE"
    BRPL_FLAG="BRPL_MODE=1"
    ;;
  *)
    echo "Unknown mode: $MODE (use rpl-lite, rpl-classic, or brpl)" >&2
    exit 2
    ;;
esac

# Build Cooja firmware images
DEFINES="SEND_INTERVAL_SECONDS=$SEND_INTERVAL"
if [ -n "$BRPL_FLAG" ]; then
  DEFINES="$DEFINES $BRPL_FLAG"
fi
make -C "$ROOT_DIR" TARGET=cooja receiver_root.cooja sender.cooja \
  MAKE_ROUTING="$MAKE_ROUTING" DEFINES="$DEFINES"

# Generate a concrete .csc for the requested node count and radio settings
python3 "$ROOT_DIR/tools/gen_csc.py" \
  --root-dir "$ROOT_DIR" \
  --senders "$SENDERS" \
  --make-routing "$MAKE_ROUTING" \
  --send-interval "$SEND_INTERVAL" \
  ${BRPL_FLAG:+--brpl} \
  --sim-time-ms "$SIM_TIME_MS" \
  --tx-range "$TX_RANGE" \
  --int-range "$INT_RANGE" \
  --success-tx "$SUCCESS_TX" \
  --success-rx "$SUCCESS_RX" \
  --out "$CSC_OUT"

# Run headless Cooja and capture logs
LOG_FILE="$LOG_DIR/${MODE}_n${SENDERS}_$(date +%Y%m%d_%H%M%S).log"
java --enable-preview -jar "$COOJA_JAR" --no-gui --autostart "$CSC_OUT" > "$LOG_FILE"

python3 "$ROOT_DIR/tools/python/log_parser.py" \
  --log "$LOG_FILE" \
  --mode "$MODE" \
  --senders "$SENDERS" \
  --send-interval "$SEND_INTERVAL" \
  --sim-time-ms "$SIM_TIME_MS" \
  --tx-range "$TX_RANGE" \
  --success-tx "$SUCCESS_TX" \
  --success-rx "$SUCCESS_RX" \
  --out "$LOG_DIR/summary.csv"

echo "Log saved: $LOG_FILE"
