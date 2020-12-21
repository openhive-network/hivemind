#!/bin/bash

set -e

pip install tox
pip install requests

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
ITERATIONS=${3:-5}
JOBS=${4:-auto}
export TAVERN_DISABLE_COMPARATOR=true

echo Attempting to start benchmarks on hivemind instance listening on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

for (( i=0; i<$ITERATIONS; i++ ))
do
  echo About to run iteration $i
  rm /tmp/test_ids.csv
  tox -e tavern-benchmark -- \
      -W ignore::pytest.PytestDeprecationWarning \
      --workers $JOBS
  echo Done!
done
./scripts/csv_report_parser.py http://$HIVEMIND_ADDRESS $HIVEMIND_PORT ./tests/tests_api/hivemind/tavern ./tests/tests_api/hivemind/tavern
