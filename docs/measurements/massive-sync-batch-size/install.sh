#!/bin/bash
# Runs in the hivemind runtime container: install reptracker + hivemind, sync reptracker.
set -euo pipefail
ADMIN_URL=postgresql://haf_admin@$PGHOST:5432/haf_block_log
USER_URL=postgresql://hivemind@$PGHOST:5432/haf_block_log
cd /src
printf "TRUNCATE TABLE version; INSERT INTO version(git_hash) VALUES ('hm470');\n" > reputation_tracker/scripts/set_version_in_sql.pgsql
export PATH=/scratch-bin:$PATH
bash scripts/setup_postgres.sh --postgres-url="$ADMIN_URL"
(cd reputation_tracker && bash scripts/install_app.sh --postgres-url="$ADMIN_URL" --schema=reptracker_app --is_forking=false)
printf "TRUNCATE TABLE hafah_backend.version; INSERT INTO hafah_backend.version(git_hash) VALUES ('hm470');\n" > hafah/scripts/set_version_in_sql.pgsql
(cd hafah && bash scripts/install_app.sh --postgres-url="$ADMIN_URL")
bash scripts/install_app.sh --reptracker-schema-name=reptracker_app --postgres-url="$ADMIN_URL"
python3 -m hive.cli build_schema --database-url="$ADMIN_URL"
bash reputation_tracker/scripts/process_blocks.sh --stop-at-block="$MAX_BLOCK" --postgres-url="$USER_URL"
echo INSTALL_DONE
