#!/bin/bash 

set -e
pip3 install tox --user

export HIVEMIND_ADDRESS=$1
export HIVEMIND_PORT=$2
export TAVERN_DISABLE_COMPARATOR=true

echo Attempting to start benchmarks on hivemind instance listeing on: $HIVEMIND_ADDRESS port: $HIVEMIND_PORT

ITERATIONS=$3

for (( i=0; i<$ITERATIONS; i++ ))
do
  echo About to run iteration $i
  tox -e tavern-benchmark -- -W ignore::pytest.PytestDeprecationWarning -n auto --junitxml=../../../../benchmarks-$i.xml 
  echo Done!
done
./scripts/xml_report_parser.py . ./tests/tests_api/hivemind/tavern
