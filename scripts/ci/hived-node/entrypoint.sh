#!/usr/bin/env bash

SCRIPT=`realpath $0`
SCRIPTPATH=`dirname $SCRIPT`

DATADIR="${SCRIPTPATH}/datadir"

HIVED="${SCRIPTPATH}/bin/hived"

ARGS="$@"
ARGS+=" "

if [[ ! -z "$TRACK_ACCOUNT" ]]; then
    ARGS+=" --plugin=account_history --plugin=account_history_api"
    ARGS+=" --account-history-track-account-range=[\"$TRACK_ACCOUNT\",\"$TRACK_ACCOUNT\"]"
fi

if [[ "$USE_PUBLIC_BLOCKLOG" ]]; then
  if [[ ! -e ${DATADIR}/blockchain/block_log ]]; then
    if [[ ! -d ${DATADIR}/blockchain ]]; then
      mkdir -p ${DATADIR}/blockchain
    fi
    echo "Hived: Downloading a block_log and replaying the blockchain"
    echo "This may take a little while..."
    wget -O ${DATADIR}/blockchain/block_log https://gtg.steem.house/get/blockchain/block_log
    ARGS+=" --replay-blockchain"
  fi
fi

"$HIVED" \
  --data-dir="${DATADIR}" \
  $ARGS \
  2>&1
