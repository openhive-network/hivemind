#!/usr/bin/env bash

# Start hived in docker container, replay up to 5000000 blocks

MYDIR="$PWD"
WORKDIR="/usr/local/hive/consensus"
IMAGE="registry.gitlab.syncad.com/hive/hive/consensus_node:00b5ff55"

docker run -d \
    --name hived-replay-5000000 \
    -p 127.0.0.1:2001:2001 \
    -p 127.0.0.1:8090:8090 \
    -p 127.0.0.1:8091:8091 \
    -v $MYDIR/config.ini:$WORKDIR/datadir/config.ini \
    -v $MYDIR/blockchain/block_log:$WORKDIR/datadir/blockchain/block_log \
    -v $MYDIR/entrypoint.sh:$WORKDIR/entrypoint.sh \
    --entrypoint $WORKDIR/entrypoint.sh \
    $IMAGE \
    --replay-blockchain --stop-at-block 5000000
