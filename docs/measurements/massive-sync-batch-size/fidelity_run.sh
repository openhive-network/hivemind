#!/bin/bash
# fidelity_run.sh LABEL SRC LIMIT MAXBLOCK [KILL_AT_BLOCK]
# One sync of a ZFS clone of the installed fixture with the tree in /scratch/hm477/SRC,
# then natural-key dumps of its data into logs/LABEL/.
set -uo pipefail
label=$1; src=$2; limit=$3; max=$4; kill_at=${5:-}
cd /scratch/hm477
RT=registry.gitlab.syncad.com/hive/hivemind/aidev-tests@sha256:5e11cad742290640c091b2f054e7d2b4684fc406e6ad6af7c00e73b007074ac7
ds=scratch/hm477-$label; mnt=/scratch/hm477-$label; pg=hm477-pg-$label; hv=hm477-hive-$label
out=logs/$label; mkdir -p $out
docker rm -f $pg $hv >/dev/null 2>&1
sudo zfs destroy -r $ds 2>/dev/null
sudo zfs clone -o mountpoint=$mnt scratch/hm477-base@installed $ds
bash pg.sh start $pg $mnt || exit 1
q() { docker exec $pg psql -h 127.0.0.1 -U haf_admin -d haf_block_log -XAtc "$1"; }
sync_once() {
  docker run --rm --name $hv --network hm477 -e PYTHONPATH=/src -v /scratch/hm477/$src:/src -w /src --entrypoint python3 $RT \
    -m hive.cli sync --database-url=postgresql://hivemind@$pg:5432/haf_block_log --reptracker-schema-name=reptracker_app \
    --test-max-block=$max --massive-sync-batch-blocks=$limit --prometheus-port 11011 --test-profile=False 2>&1 \
    | python3 -u -c 'import sys,time
for l in sys.stdin: sys.stdout.write(f"{time.time():.3f} {l}"); sys.stdout.flush()'
  return ${PIPESTATUS[0]}
}
t0=$(date +%s)
if [ -n "$kill_at" ]; then
  sync_once > $out/sync.log 2>&1 & syncpid=$!
  while sleep 1; do
    b=$(q "select coalesce((select current_block_num from hafd.contexts where name='hivemind_app'),0)" 2>/dev/null || echo 0)
    if [ "${b:-0}" -ge "$kill_at" ]; then
      # inside the next batch: WAIT_COL=posts_applied|post_data_applied waits for that phase to commit
      if [ -n "${WAIT_COL:-}" ]; then
        for i in $(seq 1200); do
          [ "$(q "select coalesce((select ${WAIT_COL}::text from hivemind_app._batch_queue), 'none')" 2>/dev/null)" = "true" ] && break
          sleep 0.5
        done
      fi
      sleep ${KILL_DELAY:-3}
      inflight=$(q "select first_block||'..'||last_block||' posts_applied='||posts_applied||' post_data_applied='||post_data_applied from hivemind_app._batch_queue" 2>/dev/null \
                 || q "select first_block||'..'||last_block from hivemind_app._batch_queue")
      docker kill $hv >/dev/null; echo "KILLED at context block $b, _batch_queue=$inflight" >> $out/sync.log
      break
    fi
  done
  wait $syncpid
  sync_once >> $out/sync.log 2>&1
else
  sync_once > $out/sync.log 2>&1
fi
rc=$?
t1=$(date +%s)
echo "label=$label src=$src limit=$limit max=$max kill_at=$kill_at rc=$rc wall_s=$((t1-t0))" > $out/result
docker cp fidelity_dump.sql $pg:/tmp/dump.sql
docker exec -w /tmp $pg bash -c "psql -h 127.0.0.1 -U haf_admin -d haf_block_log -XAtq -F '	' -f /tmp/dump.sql" >> $out/result 2>&1
for f in posts votes notifs mentions postdata counts; do docker cp $pg:/tmp/$f.txt $out/$f.txt; done
bash pg.sh stop $pg
sudo zfs destroy -r $ds
echo "RUN_DONE $label rc=$rc"
