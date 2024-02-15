#!/bin/bash

set -e
set -o pipefail

echo "Usage ./db_upgrade.sh <postgresql_url>"
rm -f ./upgrade.log

for sql in postgres_handle_view_changes.sql \
           upgrade/upgrade_table_schema.sql # Must be last

do
    echo Executing psql "$1" -f $sql
    time psql -a -1 -v "ON_ERROR_STOP=1" "$1"  -c '\timing' -f $sql 2>&1 | tee -a -i upgrade.log
  echo $?
done

time psql -a -v "ON_ERROR_STOP=1" "$1"  -c '\timing' -f upgrade/upgrade_runtime_migration.sql 2>&1 | tee -a -i upgrade.log

time psql -a -v "ON_ERROR_STOP=1" "$1"  -c '\timing' -f upgrade/do_conditional_vacuum.sql 2>&1 | tee -a -i upgrade.log

