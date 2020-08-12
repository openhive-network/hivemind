#!/bin/bash 

set -e

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
echo Attempting to start tests on hivemind instance listeing on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

echo "Selected test group (if empty all will be executed): $3"

tox -- -W ignore::pytest.PytestDeprecationWarning --junitxml=$4 $3


