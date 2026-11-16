#!/bin/bash
# profile.sh LABEL LIMIT MAXBLOCK: like run.sh, with auto_explain of nested statements over 3s
set -uo pipefail
label=$1; limit=$2; max=$3
cd /scratch/hm470
RT=registry.gitlab.syncad.com/hive/hivemind/aidev-tests@sha256:5e11cad742290640c091b2f054e7d2b4684fc406e6ad6af7c00e73b007074ac7
IMG=registry.gitlab.syncad.com/hive/haf/fixture-5m@sha256:468c5b042c1f8eb9265eeccf66879e2a0cef79d2dd169c53ede1b84431561c41
ds=scratch/hm470-$label; mnt=/scratch/hm470-$label; pg=hm470-pg-$label; hv=hm470-hive-$label
mkdir -p conf.d-$label && cp conf.d/50-perf.conf conf.d-$label/
cat > conf.d-$label/60-explain.conf <<CONF
session_preload_libraries = 'auto_explain'
auto_explain.log_min_duration = '3s'
auto_explain.log_nested_statements = on
auto_explain.log_analyze = on
auto_explain.log_timing = off
auto_explain.log_buffers = on
CONF
docker rm -f $pg $hv >/dev/null 2>&1
sudo zfs destroy -r $ds 2>/dev/null
sudo zfs clone -o mountpoint=$mnt scratch/hm470-base@installed $ds
docker run -d --name "$pg" --network hm470 --shm-size=32g -e PGCTLTIMEOUT=600 -e PG_ACCESS='host all all 0.0.0.0/0 trust' \
  -v "$mnt/haf_db_store:/home/hived/datadir/haf_db_store" -v /scratch/hm470/conf.d-$label:/home/hived/datadir/haf_postgresql_conf.d:ro \
  "$IMG" --execute-maintenance-script=/home/hived/source/./scripts/maintenance-scripts/sleep_infinity.sh >/dev/null
until docker exec "$pg" psql -h 127.0.0.1 -U haf_admin -d haf_block_log -Atc "select 1" >/dev/null 2>&1; do sleep 5; done
docker run --rm --name $hv --network hm470 -e PYTHONPATH=/src -v /scratch/hm470/src:/src -w /src --entrypoint python3 $RT \
    -m hive.cli sync --database-url=postgresql://hivemind@$pg:5432/haf_block_log --reptracker-schema-name=reptracker_app \
    --test-max-block=$max --massive-sync-batch-blocks=$limit --prometheus-port 11011 --test-profile=False > logs/$label.log 2>&1
docker exec $pg sudo -n cat /var/log/postgresql/postgresql-18-main.log > logs/$label.pglog
docker stop -t 120 $pg >/dev/null; docker rm $pg >/dev/null
echo PROFILE_DONE $label
