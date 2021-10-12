#!/bin/bash 

set -e
pip3 install tox --user

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
export TAVERN_DIR="$(realpath ./tests/api_tests/hivemind/tavern)"

echo Attempting to start tests on hivemind instance listeing on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

echo "Selected test group (if empty all will be executed): $3"

tox -e tavern -- -W ignore::pytest.PytestDeprecationWarning --workers auto --tests-per-worker auto --junitxml=../../../../$4 $3
