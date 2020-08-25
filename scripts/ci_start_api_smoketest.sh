#!/bin/bash 

set -e

cd tests/tests_api/hivemind/tavern

#pip3 install --user jsondiff==1.2.0
#pip3 install --user tavern==1.2.2
#pip3 install --user pytest==6.0.1

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
echo Attempting to start tests on hivemind instance listeing on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

echo "Selected test group (if empty all will be executed): $3"

python3 -m pytest -W ignore::pytest.PytestDeprecationWarning --junitxml=../../../../$4 $3

cd ../../../../

