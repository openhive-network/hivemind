#!/bin/bash

# set -euo pipefail

drop_db() {

    echo "Dropping database ${HIVEMIND_DB_NAME}"

    PGPASSWORD=${RUNNER_POSTGRES_ADMIN_USER_PASSWORD} dropdb \
        --if-exists \
        --username "${RUNNER_POSTGRES_ADMIN_USER}" \
        --host ${RUNNER_POSTGRES_HOST} \
        --port ${RUNNER_POSTGRES_PORT} \
        ${HIVEMIND_DB_NAME}

    RESULT=$?

    if [[ ! $RESULT -eq 0 ]]; then
        cat << EOF
ERROR: cannot drop database ${HIVEMIND_DB_NAME}.
Most often the reason is that database is used by other sessions.
This can happen on Gitlab CI server, when jobs are picked by multiple,
concurrent runners and database name is not unique on subsequent
pipelines. If this is the case, please cancel any pending pipelines
running for your branch or for your merge request, or wait until they
finish. Then retry this pipeline.
Exiting with error at this moment.
EOF
    exit $RESULT
    else
        echo "Database ${HIVEMIND_DB_NAME} has been dropped successfully"
    fi

}

drop_db
