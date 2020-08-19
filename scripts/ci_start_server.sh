#!/bin/bash 

set -xe

HIVEMIND_DB_NAME=$1
HIVEMIND_POSTGRESQL_CONNECTION_STRING=$2
HIVEMIND_SOURCE_HIVED_URL=$3
HIVEMIND_HTTP_PORT=$4

PYTHONUSERBASE=./local-site

DB_NAME=${HIVEMIND_DB_NAME//-/_}
DB_NAME=${DB_NAME//\[/_}
DB_NAME=${DB_NAME//]/_}

DB_URL=$HIVEMIND_POSTGRESQL_CONNECTION_STRING/$DB_NAME

# Reuse DB_NAME as name of symbolic link pointing local hive "binary".
HIVE_NAME=$DB_NAME

SAVED_PID=0

if [ -f hive_server.pid ]; then
  SAVED_PID=`cat hive_server.pid`
  kill -SIGINT $SAVED_PID || true;
  sleep 5
  kill -9 $SAVED_PID || true;

  rm hive_server.pid;
fi

fuser $HIVEMIND_HTTP_PORT/tcp -k -INT || true
sleep 5

fuser $HIVEMIND_HTTP_PORT/tcp -k -KILL || true
sleep 5

ls -l dist/*
rm -rf ./local-site
mkdir -p `python3 -m site --user-site`
python3 setup.py install --user --force
ln -sf ./local-site/bin/hive $HIVE_NAME
./$HIVE_NAME -h

rm -rf hive_server.log

echo Attempting to start hive server listening on $HIVEMIND_HTTP_PORT port...
screen -L -Logfile hive_server.log -dmS $HIVE_NAME ./$HIVE_NAME server --pid-file hive_server.pid --http-server-port $HIVEMIND_HTTP_PORT --steemd-url "$HIVEMIND_SOURCE_HIVED_URL" --database-url $DB_URL
for i in `seq 1 10`; do if [ -f hive_server.pid ]; then break; else sleep 1; fi;  done

SAVED_PID=`cat hive_server.pid`
LISTENING_PID=$(fuser $HIVEMIND_HTTP_PORT/tcp 2>/dev/null)
echo "Retrieved hive pid is: $SAVED_PID"
echo "Listening hive pid is: $LISTENING_PID"

cat hive_server.log 
if [ "$SAVED_PID" != "$LISTENING_PID" ]; then echo "Saved pid: $SAVED_PID vs listening pid: $LISTENING_PID mismatch..."; fi

