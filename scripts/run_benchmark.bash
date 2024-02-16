#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
echo $SCRIPTPATH
PATH_TO_CSV="$SCRIPTPATH/../haf/hive/tests/python/hive-local-tools/tests_api/benchmarks/performance_data/universal/CSV/2024_02_16_hivemind_60M_prod_sql"

PSQL_URL="postgresql://hivemind@haf/haf_block_log"
WDIR="./wdir"

mkdir -p $WDIR
cp $PATH_TO_CSV $WDIR/csv.csv

docker run \
	--rm \
	-it \
	--name haf-world-hivemind-install-1 \
       	--network haf \
	-v $WDIR:/output \
	-e ADDITIONAL_ARGS="--skip-version-check" \
	-e API=universal \
	-e CSV=/output/csv.csv \
	-e CALL_STYLE=postgres \
	-e POSTGRES_URL=$PSQL_URL \
       	-e JMETER_WORKDIR=/output/wdir \
	registry.gitlab.syncad.com/hive/tests_api/benchmark_aio:latest
