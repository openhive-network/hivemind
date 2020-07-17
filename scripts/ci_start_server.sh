#!/bin/bash 

set -e

HIVEMIND_DB_NAME=$1
HIVEMIND_POSTGRESQL_CONNECTION_STRING=$2
HIVEMIND_SOURCE_HIVED_URL=$3
HIVEMIND_HTTP_PORT=$4

PYTHONUSERBASE=./local-site

DB_NAME=${HIVEMIND_DB_NAME//-/_}
DB_NAME=${DB_NAME//\[/_}
DB_NAME=${DB_NAME//]/_}

DB_URL=$HIVEMIND_POSTGRESQL_CONNECTION_STRING/$DB_NAME

echo Attempting to start hive server listening on $HIVEMIND_HTTP_PORT port...
if [ -f hive_server.pid ]; then kill -SIGINT `cat hive_server.pid`; fi;
rm -f hive_server.pid
screen -L -Logfile hive_server.log -dmS hive_server_$CI_JOB_ID ./local-site/bin/hive server --pid-file hive_server.pid --http-server-port $HIVEMIND_HTTP_PORT --steemd-url "$HIVEMIND_SOURCE_HIVED_URL" --database-url $DB_URL
for i in `seq 1 10`; do if [ -f hive_server.pid ]; then break; else sleep 1; fi;  done
cat hive_server.pid
