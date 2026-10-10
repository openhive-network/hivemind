#!/usr/bin/env bash
# Entrypoint of the shared hivemind service (.aidev/shared-hivemind.compose.yml), run
# in the hive/haf/fixture-5m image of HAF_FIXTURE_COMMIT once cluster.sh has copied
# the cluster. Compose bind-mounts <root>/<commit>/haf_db_store directly at
# /home/hived/datadir/haf_db_store, the path the image's postgresql.conf and
# tablespace were written for. This script checks that mount holds a cluster,
# adds the clone setting and hands over to the HAF entrypoint, which starts
# PostgreSQL and then runs serve.sh.
#
# Environment: HIVEMIND_SHARED_ROOT (as cluster.sh; serve.sh reads the rest).
set -euo pipefail

root="${HIVEMIND_SHARED_ROOT:?HIVEMIND_SHARED_ROOT must name the mounted ZFS dataset}"
here="$(cd "$(dirname "$0")" && pwd -P)"
store=/home/hived/datadir/haf_db_store

# The image carries its own cluster at $store: only the device tells the
# dataset's copy apart from it.
if [ -L "$store" ] || [ "$(stat -c %d "$store")" != "$(stat -c %d "$root")" ] \
    || ! sudo -n test -f "$store/pgdata/PG_VERSION"; then
    echo "$store is not the cluster bind-mounted from the data root" >&2
    exit 1
fi

conf_d=/home/hived/datadir/haf_postgresql_conf.d
sudo -n mkdir -p "$conf_d"
sudo -n install -o postgres -g postgres -m 644 "$here/postgresql.conf" "$conf_d/50-hivemind-shared.conf"

exec /home/hived/docker_entrypoint.sh --execute-maintenance-script="$here/serve.sh"
