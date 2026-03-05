#!/bin/bash
# Run k6 performance tests against Hivemind in Docker.
#
# Usage:
#   ./run-perf-tests.sh [OPTIONS]
#
# Options:
#   --data-dir PATH       Path to pre-synced HAF datadir (required)
#   --haf-image IMAGE     HAF Docker image (default: registry.gitlab.syncad.com/hive/haf/instance:1.27.10)
#   --hivemind-image IMG  Hivemind Docker image (default: registry.gitlab.syncad.com/hive/hivemind/instance:1.27.10)
#   --script SCRIPT       k6 script to run (default: smoke.js)
#   --vus N               Virtual users (default: 10)
#   --duration DUR        Test duration (default: 2m)
#   --max-vus N           Max VUs for stress test (default: 100)
#   --json-output FILE    Save k6 JSON output to file
#   --keep                Keep services running after tests
#   --teardown            Only tear down services from a previous run
#   -h, --help            Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Defaults
HAF_DATA_DIRECTORY=""
HAF_IMAGE="registry.gitlab.syncad.com/hive/haf/instance:1.27.10"
HIVEMIND_IMAGE="registry.gitlab.syncad.com/hive/hivemind/instance:1.27.10"
K6_SCRIPT="smoke.js"
K6_VUS="10"
K6_DURATION="2m"
K6_MAX_VUS="100"
JSON_OUTPUT=""
KEEP_RUNNING=false
TEARDOWN_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --data-dir)       HAF_DATA_DIRECTORY="$2"; shift 2 ;;
    --haf-image)      HAF_IMAGE="$2"; shift 2 ;;
    --hivemind-image) HIVEMIND_IMAGE="$2"; shift 2 ;;
    --script)         K6_SCRIPT="$2"; shift 2 ;;
    --vus)            K6_VUS="$2"; shift 2 ;;
    --duration)       K6_DURATION="$2"; shift 2 ;;
    --max-vus)        K6_MAX_VUS="$2"; shift 2 ;;
    --json-output)    JSON_OUTPUT="$2"; shift 2 ;;
    --keep)           KEEP_RUNNING=true; shift ;;
    --teardown)       TEARDOWN_ONLY=true; shift ;;
    -h|--help)
      head -18 "$0" | tail -17
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

export HAF_DATA_DIRECTORY HAF_IMAGE HIVEMIND_IMAGE K6_SCRIPT K6_VUS K6_DURATION K6_MAX_VUS

compose() {
  docker compose -f docker-compose.yml "$@"
}

teardown() {
  echo "Tearing down services..."
  compose --profile test down -v --remove-orphans 2>/dev/null || true
}

if [[ "$TEARDOWN_ONLY" == "true" ]]; then
  teardown
  exit 0
fi

if [[ -z "$HAF_DATA_DIRECTORY" ]]; then
  echo "ERROR: --data-dir is required (path to pre-synced HAF datadir)"
  echo "Run with -h for usage"
  exit 1
fi

if [[ ! -d "$HAF_DATA_DIRECTORY" ]]; then
  echo "ERROR: HAF data directory does not exist: $HAF_DATA_DIRECTORY"
  exit 1
fi

trap 'if [[ "$KEEP_RUNNING" != "true" ]]; then teardown; fi' EXIT

echo "=== Starting HAF and Hivemind services ==="
echo "HAF data:   $HAF_DATA_DIRECTORY"
echo "HAF image:  $HAF_IMAGE"
echo "HM image:   $HIVEMIND_IMAGE"
echo "k6 script:  $K6_SCRIPT"
echo "VUs:        $K6_VUS"
echo ""

compose up -d haf hivemind-server

echo "Waiting for Hivemind server to be ready..."
TIMEOUT=300
START=$(date +%s)
until curl -sf "http://localhost:${HIVEMIND_PORT:-8080}/" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"hive.db_head_state","params":{}}' > /dev/null 2>&1; do
  ELAPSED=$(( $(date +%s) - START ))
  if [[ $ELAPSED -gt $TIMEOUT ]]; then
    echo "ERROR: Hivemind server did not become ready within ${TIMEOUT}s"
    compose logs hivemind-server | tail -30
    exit 1
  fi
  sleep 3
done
echo "Hivemind server is ready."
echo ""

echo "=== Running k6: $K6_SCRIPT ==="
K6_CMD="run"
if [[ -n "$JSON_OUTPUT" ]]; then
  # Run k6 directly on host for file output, connecting via localhost
  if command -v k6 > /dev/null 2>&1; then
    HIVEMIND_URL="http://localhost:${HIVEMIND_PORT:-8080}" \
    VUS="$K6_VUS" DURATION="$K6_DURATION" MAX_VUS="$K6_MAX_VUS" \
      k6 run --out "json=$JSON_OUTPUT" "k6/$K6_SCRIPT"
  else
    echo "WARNING: k6 not installed locally, running in Docker (JSON output saved inside container)"
    compose run --rm k6 run --out "json=/tests/results.json" "$K6_SCRIPT"
  fi
else
  compose run --rm k6 run "$K6_SCRIPT"
fi

echo ""
echo "=== Performance test complete ==="
