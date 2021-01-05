#!/bin/bash

set -euo pipefail

create_db() {

    echo "Creating user ${RUNNER_POSTGRES_APP_USER} and database ${HIVEMIND_DB_NAME}, owned by this user"

    TEMPLATE="template_monitoring"

    PGPASSWORD=${RUNNER_POSTGRES_ADMIN_USER_PASSWORD} psql \
        --username "${RUNNER_POSTGRES_ADMIN_USER}" \
        --host ${RUNNER_POSTGRES_HOST} \
        --port ${RUNNER_POSTGRES_PORT} \
        --dbname postgres << EOF

\echo Creating role ${RUNNER_POSTGRES_APP_USER}

DO \$$
BEGIN
    IF EXISTS (SELECT * FROM pg_user
            WHERE pg_user.usename = '${RUNNER_POSTGRES_APP_USER}') THEN
        raise warning 'Role % already exists', '${RUNNER_POSTGRES_APP_USER}';
    ELSE
        CREATE ROLE ${RUNNER_POSTGRES_APP_USER}
                WITH LOGIN PASSWORD '${RUNNER_POSTGRES_APP_USER_PASSWORD}';
    END IF;
END
\$$;

\echo Creating database ${HIVEMIND_DB_NAME}
CREATE DATABASE ${HIVEMIND_DB_NAME} TEMPLATE ${TEMPLATE}
    OWNER ${RUNNER_POSTGRES_APP_USER};
COMMENT ON DATABASE ${HIVEMIND_DB_NAME} IS
    'Database for Gitlab CI pipeline ${CI_PIPELINE_URL}, commit ${CI_COMMIT_SHORT_SHA}';

\c ${HIVEMIND_DB_NAME}

drop schema if exists hivemind_admin cascade;

create schema hivemind_admin
        authorization ${RUNNER_POSTGRES_APP_USER};

CREATE SEQUENCE hivemind_admin.database_metadata_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 2147483647
    CACHE 1;

CREATE TABLE hivemind_admin.database_metadata
(
    id integer NOT NULL DEFAULT
        nextval('hivemind_admin.database_metadata_id_seq'::regclass),
    database_name text,
    ci_pipeline_url text,
    ci_pipeline_id integer,
    commit_sha text,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT database_metadata_pkey PRIMARY KEY (id)
);

alter sequence hivemind_admin.database_metadata_id_seq
        OWNER TO ${RUNNER_POSTGRES_APP_USER};

alter table hivemind_admin.database_metadata
        OWNER TO ${RUNNER_POSTGRES_APP_USER};

insert into hivemind_admin.database_metadata
    (database_name, ci_pipeline_url, ci_pipeline_id, commit_sha)
values (
    '${HIVEMIND_DB_NAME}', '${CI_PIPELINE_URL}',
    ${CI_PIPELINE_ID}, '${CI_COMMIT_SHORT_SHA}'
    );

-- VACUUM VERBOSE ANALYZE;

\q
EOF

}

create_db
