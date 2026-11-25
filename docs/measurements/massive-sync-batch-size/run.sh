#!/bin/bash
# run.sh LABEL LIMIT MAXBLOCK [KILL_AT_BLOCK]
#   SYNC_ARGS: more `hive sync` options. Massive sync is pipelined by default (#523): a sequential
#     run passes SYNC_ARGS=--massive-sync-pipelined=false (the README's results ran sequential)
set -uo pipefail
label=$1; limit=$2; max=$3; kill_at=${4:-}
cd /scratch/hm470
RT=registry.gitlab.syncad.com/hive/hivemind/aidev-tests@sha256:5e11cad742290640c091b2f054e7d2b4684fc406e6ad6af7c00e73b007074ac7
ds=scratch/hm470-$label; mnt=/scratch/hm470-$label; pg=hm470-pg-$label; hv=hm470-hive-$label
docker rm -f $pg $hv >/dev/null 2>&1
sudo zfs destroy -r $ds 2>/dev/null
sudo zfs clone -o mountpoint=$mnt scratch/hm470-base@installed $ds
bash pg.sh start $pg $mnt || exit 1
q() { docker exec $pg psql -h 127.0.0.1 -U haf_admin -d haf_block_log -XAtc "$1"; }
q "select pg_stat_reset()" >/dev/null
temp0=$(q "select temp_files||' '||temp_bytes from pg_stat_database where datname='haf_block_log'")
python3 sampler.py logs/$label.mem.json $pg $hv & sp=$!
python3 activity_sampler.py logs/$label.activity.jsonl $pg & ap=$!
sync_once() {
  docker run --rm --name $hv --network hm470 -e PYTHONPATH=/src -v /scratch/hm470/src:/src -w /src --entrypoint python3 $RT \
    -m hive.cli sync --database-url=postgresql://hivemind@$pg:5432/haf_block_log --reptracker-schema-name=reptracker_app \
    --test-max-block=$max --massive-sync-batch-blocks=$limit --prometheus-port 11011 --test-profile=False ${SYNC_ARGS:-} 2>&1 \
    | python3 -u -c 'import sys,time
for l in sys.stdin: sys.stdout.write(f"{time.time():.3f} {l}"); sys.stdout.flush()'
  return ${PIPESTATUS[0]}
}
t0=$(date +%s)
if [ -n "$kill_at" ]; then
  sync_once > logs/$label.log 2>&1 & syncpid=$!
  while sleep 1; do
    b=$(q "select coalesce((select current_block_num from hafd.contexts where name='hivemind_app'),0)" 2>/dev/null || echo 0)
    if [ "${b:-0}" -ge "$kill_at" ]; then
      sleep 3  # inside the next batch
      inflight=$(q "select first_block||'..'||last_block from hivemind_app._batch_queue")
      docker kill $hv >/dev/null; echo "KILLED at context block $b, _batch_queue=$inflight" >> logs/$label.log
      break
    fi
  done
  wait $syncpid
  sync_once >> logs/$label.log 2>&1
else
  sync_once > logs/$label.log 2>&1
fi
rc=$?
t1=$(date +%s)
kill $sp $ap; wait $sp $ap
python3 activity_sampler.py --summary logs/$label.activity.jsonl > logs/$label.activity.txt
temp1=$(q "select temp_files||' '||temp_bytes from pg_stat_database where datname='haf_block_log'")
docker exec $pg sudo -n grep -h "temporary file" /var/log/postgresql/postgresql-18-main.log > logs/$label.temp.log 2>/dev/null
maxtemp=$(grep -o 'size [0-9]*' logs/$label.temp.log | awk '{print $NF}' | sort -n | tail -1)
{
  echo "label=$label limit=$limit max=$max rc=$rc wall_s=$((t1-t0)) temp_before=$temp0 temp_after=$temp1 max_temp_file=${maxtemp:-0}"
  docker exec -i $pg psql -h 127.0.0.1 -U haf_admin -d haf_block_log -XAt < digest.sql
} > logs/$label.result
bash pg.sh stop $pg
echo "RUN_DONE $label rc=$rc"
