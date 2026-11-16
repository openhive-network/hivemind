#!/bin/bash
# pg.sh start|stop NAME DATASET_MOUNT
set -euo pipefail
IMG=registry.gitlab.syncad.com/hive/haf/fixture-5m@sha256:468c5b042c1f8eb9265eeccf66879e2a0cef79d2dd169c53ede1b84431561c41
cmd=$1; name=$2; mnt=${3:-}
case $cmd in
start)
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker run -d --name "$name" --network hm470 --shm-size=32g \
    -e PGCTLTIMEOUT=600 -e PG_ACCESS='host all all 0.0.0.0/0 trust' \
    -v "$mnt/haf_db_store:/home/hived/datadir/haf_db_store" \
    -v /scratch/hm470/conf.d:/home/hived/datadir/haf_postgresql_conf.d:ro \
    "$IMG" --execute-maintenance-script=/home/hived/source/./scripts/maintenance-scripts/sleep_infinity.sh >/dev/null
  for i in $(seq 120); do
    docker exec "$name" psql -h 127.0.0.1 -U haf_admin -d haf_block_log -Atc "select 1" >/dev/null 2>&1 && { echo "$name up"; exit 0; }
    sleep 5
  done
  docker logs --tail 50 "$name"; exit 1;;
stop)
  docker stop -t 120 "$name" >/dev/null && docker rm "$name" >/dev/null; echo "$name stopped";;
esac
