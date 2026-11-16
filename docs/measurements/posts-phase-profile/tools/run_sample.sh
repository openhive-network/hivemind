#!/bin/bash
# aidev hivemind#472: one profiling sample on the steem-19 clone.
# usage: run_sample.sh <name> <logged|unlogged> <auto_explain 0|1> <last block>
# Set HM_MOUNTS to extra docker run options for the hivemind container (e.g. patched SQL
# scripts bind-mounted over the image's; hivemind reinstalls its SQL at every start).
# Rolls the clone back to @s19, optionally makes the 8 large tables UNLOGGED, prewarms
# the posts-phase relations, runs hivemind's massive sync until <last block>, and saves
# pg_stat_statements, pg_stat_wal, pg_stat_io and the PHASE-SUMMARY lines in ~/aidev472/<name>/.
set -euo pipefail
NAME=$1 MODE=$2 AE=$3 LAST=$4
OUT=~/aidev472/$NAME; mkdir -p "$OUT"
D=/haf-pool/aidev472 T=haf-pool/aidev472
P="docker exec -i -u postgres aidev472-haf psql -d haf_block_log -X -q -v ON_ERROR_STOP=1"
log() { date -u +"%F %T $*" | tee -a "$OUT/run.log"; }

log "stop postgres, roll back to @s19"
docker exec aidev472-haf sudo -n /etc/init.d/postgresql stop >/dev/null 2>&1 || true; docker stop -t 30 aidev472-haf >/dev/null
for ds in $(zfs list -H -o name -r $T); do sudo zfs rollback -r "$ds@s19"; done
if [ "$AE" = 1 ]; then
  sudo tee $D/haf_postgresql_conf.d/zzz-aidev472-ae.conf >/dev/null <<CONF
log_destination = 'jsonlog'
auto_explain.log_min_duration = 0
auto_explain.log_analyze = on
auto_explain.log_buffers = on
auto_explain.log_wal = on
auto_explain.log_timing = on
auto_explain.log_nested_statements = on
auto_explain.log_format = json
CONF
  sudo chown --reference=$D/haf_postgresql_conf.d/pgtune.conf $D/haf_postgresql_conf.d/zzz-aidev472-ae.conf
fi
docker start aidev472-haf >/dev/null
until echo "select 1" | $P >/dev/null 2>&1; do sleep 2; done
log "postgres up"

if [ "$MODE" = unlogged ]; then
  t0=$(date +%s)
  for t in hive_reblogs hive_mentions hive_votes hive_post_data hive_posts hive_permlink_data hive_post_tags hive_accounts; do
    echo "ALTER TABLE hivemind_app.$t SET UNLOGGED;" | $P
  done
  log "SET UNLOGGED on 8 tables took $(( $(date +%s) - t0 )) s"
fi
echo "select relname, relpersistence from pg_class where relnamespace='hivemind_app'::regnamespace and relname in ('hive_votes','hive_post_data','hive_posts','hive_permlink_data','hive_post_tags','hive_accounts','hive_reblogs','hive_mentions') order by 1;" | $P > "$OUT/persistence.txt"

cat <<SQL | $P > "$OUT/prewarm.txt"
CREATE EXTENSION IF NOT EXISTS pg_prewarm;
SELECT c.relname, pg_prewarm(c.oid) FROM pg_class c WHERE c.relnamespace = 'hivemind_app'::regnamespace
  AND c.relname IN ('hive_posts','hive_posts_pkey','hive_posts_ux1','hive_permlink_data','hive_permlink_data_permlink','hive_permlink_data_pkey',
                    'hive_accounts','hive_accounts_pkey','hive_accounts_ux1','hive_category_data','hive_category_data_category','hive_category_data_pkey',
                    'hive_tag_data','hive_tag_data_ux1','hive_post_tags','hive_post_tags_idx','hive_post_tags_tag_id_post_id_idx');
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset_shared('wal');
SELECT pg_stat_reset_shared('io');
SELECT pg_stat_reset_shared('checkpointer');
SQL
log "prewarmed, stats reset; starting sync"
docker rm -f aidev472-hm-$NAME >/dev/null 2>&1 || true
docker run -d --name aidev472-hm-$NAME --network aidev472-net ${HM_MOUNTS:-} aidev472/hivemind:ba5c5943 sync \
  --database-url=postgresql://hivemind@aidev472-haf/haf_block_log \
  --database-admin-url=postgresql://haf_admin@aidev472-haf/haf_block_log >/dev/null
# HM_MOUNTS: extra docker run options (e.g. -v patched.sql:/path/in/image:ro), placed before the image
until docker logs --since 2m aidev472-hm-$NAME 2>&1 | grep -q "PHASE-SUMMARY\] blocks=[0-9]*-$LAST "; do
  docker ps --format '{{.Names}}' | grep -q "^aidev472-hm-$NAME$" || { log "sync exited early"; break; }
  sleep 2
done
log "reached $LAST, stopping"
docker stop -t 1800 aidev472-hm-$NAME >/dev/null
log "stopped"
docker logs aidev472-hm-$NAME > "$OUT/hivemind.log" 2>&1
grep -F "[PHASE-SUMMARY]" "$OUT/hivemind.log" > "$OUT/phase.txt" || true
$P < ~/aidev472/pss_dump.sql > "$OUT/pss.tsv"
$P < ~/aidev472/pss_queries.sql > "$OUT/queries.tsv"
$P < ~/aidev472/sizes.sql > "$OUT/sizes.tsv"
echo "select proname, prosrc like '%TRUNCATE%' AS truncates from pg_proc where proname in ('process_root_posts_batch','process_comments_batch','process_posts_from_staging');" | $P > "$OUT/functions.txt"
echo "\\pset format unaligned
select * from pg_stat_wal; select * from pg_stat_checkpointer;
select backend_type, object, context, reads, read_bytes, writes, write_bytes, extends, hits, evictions, fsyncs from pg_stat_io where reads+writes+extends+hits > 0 order by hits desc nulls last;" | $P > "$OUT/stats.txt"
if [ "$AE" = 1 ]; then
  docker exec aidev472-haf sudo -n /etc/init.d/postgresql stop >/dev/null 2>&1 || true; docker stop -t 30 aidev472-haf >/dev/null
  sudo cp $D/logs/postgresql/postgresql.json "$OUT/postgresql.json"; sudo chown syncad "$OUT/postgresql.json"
  sudo rm -f $D/haf_postgresql_conf.d/zzz-aidev472-ae.conf
  docker start aidev472-haf >/dev/null
fi
log "done"
