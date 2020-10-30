#!/bin/bash

# TODO This script needs review.

set -euo pipefail

HIVEMIND_PID=0
MERCY_KILL_TIMEOUT=5
START_DELAY=5

# For debug only!
# HIVED_URL='{"default":"http://hived-node:8091"}'
# HIVED_URL='{"default":"http://172.17.0.1:8091"}'
# HIVED_URL='{"default":"http://127.0.0.1:8091"}'
# HIVEMIND_HTTP_PORT="8080"
# HIVEMIND_POSTGRESQL_CONNECTION_STRING="postgresql://syncad:devdev@localhost:5432/hive_test"

check_pid() {
  if [ -f hive_server.pid ]; then
    HIVEMIND_PID=`cat hive_server.pid`
    if ps -p $HIVEMIND_PID > /dev/null
    then
      # Process is running
      echo "Process pid $HIVEMIND_PID is running"
    else
      # Process is not running
      rm hive_server.pid
      HIVEMIND_PID=0
    fi
  else
    HIVEMIND_PID=0
  fi
}

stop() {
  if [ "$HIVEMIND_PID" -gt "0" ]; then
    HIVEMIND_PID=`cat hive_server.pid`

    # Send INT signal and give it some time to stop.
    echo "Stopping hive server (pid $HIVEMIND_PID) gently (SIGINT)"
    kill -SIGINT $HIVEMIND_PID || true;
    sleep $MERCY_KILL_TIMEOUT

    # Send TERM signal. Kill to be sure.
    echo "Killing hive server (pid $HIVEMIND_PID) to be sure (SIGTERM)"
    kill -9 $HIVEMIND_PID > /dev/null 2>&1 || true;

    rm hive_server.pid;
    echo "Hive server has been stopped"
  else
    echo "Hive server is not running"
  fi
}


start() {

  if [ "$HIVEMIND_PID" -gt "0" ]; then
    echo "Hive server is already running (pid $HIVEMIND_PID)"
    exit 0
  fi

  echo "Starting hive server on port ${HIVEMIND_HTTP_PORT}"

  hive server \
      --log-mask-sensitive-data \
      --pid-file hive_server.pid \
      --http-server-port $HIVEMIND_HTTP_PORT \
      --steemd-url "$HIVED_URL" \
      --database-url "$HIVEMIND_POSTGRESQL_CONNECTION_STRING" 2>&1 \
      | tee -ia hivemind-server.log &

  HIVEMIND_PID=$!

  for i in `seq 1 10`; do
    if [ -f hive_server.pid ]; then
      echo "Starting hive server (pid $HIVEMIND_PID)"
      # Wait some time to allow its initialization.
      sleep $START_DELAY
      # Check if process is still running.
      if ps -p $HIVEMIND_PID > /dev/null
      then
        echo "Hive server is running (pid $HIVEMIND_PID)"
        exit 0
      else
        # Check if process executed successfully or not.
        if wait $HIVEMIND_PID; then
          echo "Hive server has been started (pid $HIVEMIND_PID)"
          exit 0
        else
          RESULT=$?
          echo "Hive server terminated abnormally (returned $RESULT)"
          rm hive_server.pid;
          exit $RESULT
        fi
      fi
    else
      sleep 1
    fi
  done

  # If we are here, something went wrong.
  echo "Timeout reached. Hive server has not been started, exiting."
  rm hive_server.pid;
  exit 1

}


check_pid
"$1"
