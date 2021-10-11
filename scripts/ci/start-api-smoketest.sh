#!/bin/bash

set -e

# Existence of file `tox-installed` means that a preceding script
# has installed tox already.
if [ ! -f "tox-installed" ]; then
    pip3 install tox
fi

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
TEST_GROUP=$3
JUNITXML=$4
JOBS=${5:-auto}
export TAVERN_DIR="$(realpath ./tests/api_tests/hivemind/tavern)"

echo "Starting tests on hivemind server running on ${HIVEMIND_ADDRESS}:${HIVEMIND_PORT}"

echo "Selected test group (if empty all will be executed): $TEST_GROUP"

tox -e tavern -- \
    -W ignore::pytest.PytestDeprecationWarning \
    --workers $JOBS \
    --tests-per-worker auto \
    --junitxml=../../../../$JUNITXML $TEST_GROUP
