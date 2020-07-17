#!/bin/bash 

set -e

HIVEMIND_DB_NAME=$1
HIVEMIND_POSTGRESQL_CONNECTION_STRING=$2
HIVEMIND_SOURCE_HIVED_URL=$3
HIVEMIND_MAX_BLOCK=$4

PYTHONUSERBASE=./local-site

DB_NAME=${HIVEMIND_DB_NAME/-/_}
DB_URL=$HIVEMIND_POSTGRESQL_CONNECTION_STRING/$DB_NAME
echo Corrected db name $DB_NAME
echo Corrected db url $DB_URL
ls -l dist/*
rm -rf ./local-site
mkdir -p `python3 -m site --user-site`
python3 setup.py install --user --force
./local-site/bin/hive -h
echo Attempting to recreate database $DB_NAME
psql -U $POSTGRES_USER -h localhost -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
psql -U $POSTGRES_USER -h localhost -d postgres -c "CREATE DATABASE $DB_NAME;"
echo Attempting to starting hive sync using hived node: $HIVEMIND_SOURCE_HIVED_URL . Max sync block is: $HIVEMIND_MAX_BLOCK
echo Attempting to access database $DB_URL
./local-site/bin/hive sync --test-max-block=$HIVEMIND_MAX_BLOCK --exit-after-sync --test-profile=False --steemd-url "$HIVEMIND_SOURCE_HIVED_URL" --database-url $DB_URL 2>&1 | tee -i hivemind-sync.log
