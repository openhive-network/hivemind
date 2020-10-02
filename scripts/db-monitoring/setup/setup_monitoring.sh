#!/bin/bash

# Create stuff for monitoring.

DB_NAME=${1:-template_hive_ci}
SETUP_MONITORING_PGWATCH2=${2:-yes}
SETUP_MONITORING_PGHERO=${3:-yes}
CREATE_TEMPLATE=${4:-yes}
CREATE_DB_PGHERO=${5:-yes}

if [ -z "$PSQL_OPTIONS" ]; then
    PSQL_OPTIONS="-p 5432 -U postgres -h 127.0.0.1"
fi

setup_monitoring_pgwatch2() {
    # Install stuff for pgwatch2 into database under monitoring.
    psql $PSQL_OPTIONS -f ./create_role_pgwatch2.sql
    psql $PSQL_OPTIONS -d $DB_NAME -f ./setup_monitoring_pgwatch2.sql
}

setup_monitoring_pghero() {
    # Install stuff for pghero into database under monitoring
    psql $PSQL_OPTIONS -f ./create_role_pghero.sql
    psql $PSQL_OPTIONS -d $DB_NAME -f ./setup_monitoring_pghero.sql
}

create_db_pghero() {
    # Create database for pghero for collecting historical stats data.
    psql $PSQL_OPTIONS -f ./create_database_pghero.sql
    psql postgresql://pghero:pghero@127.0.0.1:5432/pghero -f ./create_tables_pghero.sql
}

create_template() {
    # Create template database.
    echo "Creating template database $DB_NAME"
    psql $PSQL_OPTIONS -f ./create_template.sql --set=db_name=$DB_NAME
}

lock_template() {
    # Lock connections to template database.
    echo "Locking connections to template database $DB_NAME"
    psql $PSQL_OPTIONS -f ./setup_template.sql --set=db_name=$DB_NAME
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
