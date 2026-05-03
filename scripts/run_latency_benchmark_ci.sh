#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${AURORA_PERF_OUT_DIR:-artifacts/perf}/latency"
SERVER_LOG="${OUT_DIR}/server.log"
URL="${AURORA_LATENCY_URL:-http://127.0.0.1:8080/}"
DURATION="${AURORA_LATENCY_DURATION_SEC:-8}"
WARMUP="${AURORA_LATENCY_WARMUP_SEC:-2}"
CONNECTIONS="${AURORA_LATENCY_CONNECTIONS:-16}"
COMPILER="${DC:-ldc2}"

usage() {
  cat <<'USAGE'
Usage: scripts/run_latency_benchmark_ci.sh

Runs the Aurora benchmark server with DUB, measures latency percentiles, writes
artifacts under artifacts/perf/latency, and enforces the conservative guard in
benchmarks/latency/baseline.json.

Environment overrides:
  AURORA_PERF_OUT_DIR              root artifact directory (default: artifacts/perf)
  AURORA_LATENCY_URL               target URL (default: http://127.0.0.1:8080/)
  AURORA_LATENCY_DURATION_SEC      measured duration (default: 8)
  AURORA_LATENCY_WARMUP_SEC        warmup duration (default: 2)
  AURORA_LATENCY_CONNECTIONS       parallel keep-alive connections (default: 16)
  DC                               D compiler passed to DUB (default: ldc2)
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$OUT_DIR"

if ! command -v dub >/dev/null 2>&1; then
  echo "ERROR: dub is required" >&2
  exit 127
fi

if ! command -v "$COMPILER" >/dev/null 2>&1; then
  echo "ERROR: D compiler '$COMPILER' is required" >&2
  exit 127
fi

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "Starting Aurora benchmark server..."
dub run --single benchmarks/server.d --compiler="$COMPILER" --build=release >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

echo "Waiting for server readiness at ${URL}..."
READY=0
for _ in $(seq 1 60); do
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    echo "ERROR: benchmark server exited before readiness" >&2
    cat "$SERVER_LOG" >&2 || true
    exit 1
  fi

  if python3 - "$URL" <<'PY'
import http.client
import sys
from urllib.parse import urlparse

url = urlparse(sys.argv[1])
conn = http.client.HTTPConnection(url.hostname, url.port or 80, timeout=1.0)
try:
    conn.request("GET", url.path or "/")
    response = conn.getresponse()
    response.read()
    raise SystemExit(0 if response.status < 500 else 1)
except Exception:
    raise SystemExit(1)
finally:
    try:
        conn.close()
    except Exception:
        pass
PY
  then
    READY=1
    break
  fi
  sleep 1
done

if [[ "$READY" -ne 1 ]]; then
  echo "ERROR: benchmark server did not become ready" >&2
  cat "$SERVER_LOG" >&2 || true
  exit 1
fi

python3 benchmarks/latency/hdr_latency.py \
  --url "$URL" \
  --duration-sec "$DURATION" \
  --warmup-sec "$WARMUP" \
  --connections "$CONNECTIONS" \
  --out-dir "$OUT_DIR" \
  --baseline benchmarks/latency/baseline.json

if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -f "${OUT_DIR}/latency_report.md" ]]; then
  {
    echo "## Aurora latency benchmark"
    cat "${OUT_DIR}/latency_report.md"
  } >> "$GITHUB_STEP_SUMMARY"
fi
