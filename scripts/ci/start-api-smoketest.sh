#!/bin/bash

set -euo pipefail

export HIVEMIND_ADDRESS="$1"
export HIVEMIND_PORT="$2"
TEST_GROUP="$3"
JUNITXML="$4"
JOBS=${5:-"auto"}

TAVERN_DIR="$(realpath ./tests/api_tests/hivemind/tavern)"
export TAVERN_DIR

echo HIVEMIND_ADDRESS: "${HIVEMIND_ADDRESS}"
echo HIVEMIND_PORT: "${HIVEMIND_PORT}"
echo TEST_GROUP: "${TEST_GROUP}"
echo JUNITXML: "${JUNITXML}"
echo JOBS: "${JOBS}"

echo "Starting tests on hivemind server running on ${HIVEMIND_ADDRESS}:${HIVEMIND_PORT}"

echo "Selected test group (if empty all will be executed): ${TEST_GROUP}"

tox -e tavern -- \
  -W ignore::pytest.PytestDeprecationWarning \
  -n "${JOBS}" \
  --junitxml=../../../../"${JUNITXML}" "${TEST_GROUP}"
