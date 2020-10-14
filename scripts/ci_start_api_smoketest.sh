#!/bin/bash 

set -e
pip3 install tox --user

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
export TAVERN_DIR="tests/tests_api/hivemind/tavern"

echo Attempting to start tests on hivemind instance listeing on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

echo "Selected test group (if empty all will be executed): $3"

tox -- -W ignore::pytest.PytestDeprecationWarning -n auto --durations=0 --junitxml=../../../../$4 $3
