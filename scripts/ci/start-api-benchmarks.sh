#!/bin/bash

set -euo pipefail

export HIVEMIND_ADDRESS="$1"
export HIVEMIND_PORT="$2"
ITERATIONS=${3:-5}
JOBS=${4:-"auto"}

TAVERN_DIR="$(realpath ./tests/api_tests/hivemind/tavern)"
export TAVERN_DIR

echo "HIVEMIND_ADDRESS: ${HIVEMIND_ADDRESS}"
echo "HIVEMIND_PORT: ${HIVEMIND_PORT}"
echo "ITERATIONS: ${ITERATIONS}"
echo "JOBS: ${JOBS}"

# since it working inside docker it shoud be fine to hardcode it to tmp
export HIVEMIND_BENCHMARKS_IDS_FILE=/tmp/test_ids.csv
export TAVERN_DISABLE_COMPARATOR=true

echo "Removing old files"

rm -f ./tavern_benchmarks_report.html
rm -f "${TAVERN_DIR}/benchmark.csv"

echo "Attempting to start benchmarks on hivemind instance listening on: ${HIVEMIND_ADDRESS}:${HIVEMIND_PORT}"

for ((i = 0; i < ITERATIONS; i++)); do
  echo "About to run iteration ${i}"
  rm -f HIVEMIND_BENCHMARKS_IDS_FILE
  tox -e tavern-benchmark -- \
    -W ignore::pytest.PytestDeprecationWarning \
    -n "${JOBS}" \
    -m "not postgrest_exception" \
    "${@:5}"
  echo "Done!"
done
tox -e csv-report-parser -- "http://${HIVEMIND_ADDRESS}" "${HIVEMIND_PORT}" "${TAVERN_DIR}" "${TAVERN_DIR}" --time-threshold=2.0
