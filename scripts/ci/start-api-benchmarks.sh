#!/bin/bash

set -e

pip install tox
pip install requests

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
ITERATIONS=${3:-5}
JOBS=${4:-auto}

export HIVEMIND_BENCHMARKS_IDS_FILE=$5
export TAVERN_DIR=$6

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
      --workers $JOBS
  echo Done!
done
./scripts/csv_report_parser.py http://$HIVEMIND_ADDRESS $HIVEMIND_PORT $TAVERN_DIR $TAVERN_DIR
