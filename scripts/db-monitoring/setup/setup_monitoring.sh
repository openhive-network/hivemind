#!/bin/bash

# Create stuff for monitoring.

set -e

DB_NAME=${1:-template_monitoring}
SETUP_MONITORING_PGWATCH2=${2:-yes}
SETUP_MONITORING_PGHERO=${3:-yes}
CREATE_TEMPLATE=${4:-yes}
CREATE_DB_PGHERO=${5:-no}
SQL_SCRIPTS_PATH=$PWD/sql-monitoring

if [ -z "$PSQL_OPTIONS" ]; then
    # PSQL_OPTIONS="-p 5432 -U postgres -h 127.0.0.1"
    PSQL_OPTIONS=""
fi

setup_monitoring_pgwatch2() {
    echo "Creating role and stuff for pgwatch2"
    psql $PSQL_OPTIONS -f $SQL_SCRIPTS_PATH/20_create_role_pgwatch2.sql
    psql $PSQL_OPTIONS -d $DB_NAME -f $SQL_SCRIPTS_PATH/30_setup_monitoring_pgwatch2.sql
}

setup_monitoring_pghero() {
    echo "Creating role and stuff for pghero"
    psql $PSQL_OPTIONS -f $SQL_SCRIPTS_PATH/21_create_role_pghero.sql
    psql $PSQL_OPTIONS -d $DB_NAME -f $SQL_SCRIPTS_PATH/31_setup_monitoring_pghero.sql
}

create_db_pghero() {
    echo "Creating database pghero for collecting historical stats data"
    psql $PSQL_OPTIONS -f $SQL_SCRIPTS_PATH/40_create_database_pghero.sql
    psql postgresql://pghero:pghero@127.0.0.1:5432/pghero -f $SQL_SCRIPTS_PATH/41_create_tables_pghero.sql
}

create_template() {
    echo "Creating database $DB_NAME"
    psql $PSQL_OPTIONS -f $SQL_SCRIPTS_PATH/10_create_template.sql --set=db_name=$DB_NAME
}

lock_template() {
    echo "Locking connections to database $DB_NAME"
    psql $PSQL_OPTIONS -f $SQL_SCRIPTS_PATH/50_setup_template.sql --set=db_name=$DB_NAME
}

main() {

    # Run flow.

    if [ "$CREATE_TEMPLATE" = "yes" ]; then
        create_template
    fi

    if [ "$SETUP_MONITORING_PGWATCH2" = "yes" ]; then
        setup_monitoring_pgwatch2
    fi

    if [ "$SETUP_MONITORING_PGHERO" = "yes" ]; then
        setup_monitoring_pghero
    fi

    if [ "$CREATE_DB_PGHERO" = "yes" ]; then
        create_db_pghero
    fi

    if [ "$CREATE_TEMPLATE" = "yes" ]; then
        lock_template
    fi

}

main
