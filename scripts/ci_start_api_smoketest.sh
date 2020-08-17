#!/bin/bash 

set -e

cd tests/tests_api/hivemind/tavern

pip3 install --user jsondiff==1.2.0
pip3 install --user tavern==1.2.2
pip3 install --user pytest==6.0.1
# package for multithraded test execution
pip3 install --user pytest-xdist
pip3 install --user deepdiff[murmur]

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
echo Attempting to start tests on hivemind instance listeing on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

echo "Selected test group (if empty all will be executed): $3"

# -n -- number of thread to run tests with
# --durations=x show x slowest tests with execution time, 0 show execution time of all tests
python3 -m pytest -W ignore::pytest.PytestDeprecationWarning -n auto --durations=0 --junitxml=../../../../$4 $3

cd ../../../../

