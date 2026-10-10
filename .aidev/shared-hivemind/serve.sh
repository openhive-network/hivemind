#!/usr/bin/env bash
# Maintenance script of the shared hivemind service, run by the HAF entrypoint
# once PostgreSQL is up (start.sh hands it over):
#
# 1. installs the clone API (admin.sql) into the hivemind_shared database;
# 2. once per HAF commit, freezes haf_template: a clone of haf_block_log that no
#    one may connect to, which seed.sh clones for every revision it syncs.
#    haf_block_log itself stays connectable, because the entrypoint checks and
#    updates the extension in it on every start;
# 3. reaps run databases every HIVEMIND_SHARED_REAP_INTERVAL seconds, then
#    serves as the image's sleep_infinity.sh does.
#
# The templates themselves come from the `seeder` service (seeder.sh).
#
# Environment: HIVEMIND_SHARED_RUN_TTL (default '6 hours'),
# HIVEMIND_SHARED_REAP_INTERVAL (default 300).
set -euo pipefail

ttl="${HIVEMIND_SHARED_RUN_TTL:-6 hours}"
interval="${HIVEMIND_SHARED_REAP_INTERVAL:-300}"
here="$(cd "$(dirname "$0")" && pwd -P)"

psql_pg() {
    sudo -nu postgres psql -X -q -v ON_ERROR_STOP=1 "$@"
}

psql_pg -d postgres <<'SQL'
select 'create database hivemind_shared' where not exists (select 1 from pg_database where datname = 'hivemind_shared')
\gexec
SQL
psql_pg -d hivemind_shared -f "$here/admin.sql"

if [ "$(psql_pg -d postgres -Atc "select count(*) from pg_database where datname = 'haf_template' and datistemplate")" != 1 ]; then
    echo "freezing haf_template from haf_block_log"
    # A template left by an interrupted freeze is not marked: start it over.
    psql_pg -d postgres -c 'drop database if exists haf_template'
    psql_pg -d postgres -c 'create database haf_template template haf_block_log strategy file_copy'
    psql_pg -d postgres -c 'alter database haf_template is_template true allow_connections false'
fi
psql_pg -d hivemind_shared -c 'select * from hivemind_shared.health()'

reap() {
    while sleep "$interval"; do
        psql_pg -d hivemind_shared -At -v ttl="$ttl" <<'SQL' || echo "reaping run databases failed; retrying in ${interval}s" >&2
select 'reaped ' || hivemind_shared.reap_run_databases(:'ttl');
SQL
    done
}
reap &

exec "$HAF_SOURCE_DIR/scripts/maintenance-scripts/sleep_infinity.sh"
