#!/bin/bash 

set -e
pip3 install tox --user
pip3 install requests --user

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
export TAVERN_DISABLE_COMPARATOR=true

echo Attempting to start benchmarks on hivemind instance listeing on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

ITERATIONS=$3

for (( i=0; i<$ITERATIONS; i++ ))
do
  echo About to run iteration $i
  rm /tmp/test_ids.csv
  tox -e tavern-benchmark -- -W ignore::pytest.PytestDeprecationWarning --workers auto
  echo Done!
done
./scripts/csv_report_parser.py http://$HIVEMIND_ADDRESS $HIVEMIND_PORT./tests/tests_api/hivemind/tavern ./tests/tests_api/hivemind/tavern
