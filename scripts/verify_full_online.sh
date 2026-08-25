#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
LOG_FILE=/tmp/boardgame-full-e2e-server.log

cd "$PROJECT_DIR/server"
TURN_DURATION_MS=800 PORT=8080 npm start >"$LOG_FILE" 2>&1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

attempt=0
until curl -fsS http://127.0.0.1:8080/health >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 50 ]; then
    echo "Local server did not start. Log: $LOG_FILE" >&2
    exit 1
  fi
  sleep 0.1
done

cd "$PROJECT_DIR"
BOARDGAME_SERVER_URL=ws://127.0.0.1:8080/ws godot --headless --path client --script res://tests/FullOnlineGameE2E.gd
