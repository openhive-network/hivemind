#!/bin/bash

set -e

pip3 install tox
pip3 install requests

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
ITERATIONS=${3:-5}
JOBS=${4:-auto}
export TAVERN_DIR=$5

# since it working inside docker it shoud be fine to hardcode it to tmp
export HIVEMIND_BENCHMARKS_IDS_FILE=/tmp/test_ids.csv
export TAVERN_DISABLE_COMPARATOR=true

echo Removing old files

rm -f ./tavern_benchmarks_report.html
rm -f $TAVERN_DIR/benchmark.csv

echo Attempting to start benchmarks on hivemind instance listening on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

for (( i=0; i<$ITERATIONS; i++ ))
do
  echo About to run iteration $i
  rm -f HIVEMIND_BENCHMARKS_IDS_FILE
  tox -e tavern-benchmark -- \
      -W ignore::pytest.PytestDeprecationWarning \
      --workers $JOBS \
      "${@:6}"
  echo Done!
done
./scripts/csv_report_parser.py http://$HIVEMIND_ADDRESS $HIVEMIND_PORT $TAVERN_DIR $TAVERN_DIR
