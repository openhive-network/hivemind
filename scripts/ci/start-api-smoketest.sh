#!/bin/bash

set -e
pip install tox

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
export TAVERN_DIR="tests/tests_api/hivemind/tavern"

echo "Starting tests on hivemind server running on ${HIVEMIND_ADDRESS}:${HIVEMIND_PORT}"

echo "Selected test group (if empty all will be executed): $3"

tox -- -W ignore::pytest.PytestDeprecationWarning -n auto --durations=0 \
        --junitxml=../../../../$4 $3
