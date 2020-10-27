#!/bin/bash

set -euo pipefail

# TODO We have troubles with user, when postgresql is run from docker.
# We need user name `postgres`, not other, I'm afraid.
# ADMIN_POSTGRES_USER=postgres
# ADMIN_POSTGRES_USER_PASSWORD=postgres

create_db() {

    echo "Creating user ${HIVEMIND_POSTGRES_USER} and database ${HIVEMIND_DB_NAME}, owned by this user"

    PGPASSWORD=${ADMIN_POSTGRES_USER_PASSWORD} psql \
        --username "${ADMIN_POSTGRES_USER}" \
        --host ${POSTGRES_HOST} \
        --port ${POSTGRES_PORT} \
        --dbname postgres << EOF

\echo Creating role ${HIVEMIND_POSTGRES_USER}

DO \$$
BEGIN
    IF EXISTS (SELECT * FROM pg_user
            WHERE pg_user.usename = '${HIVEMIND_POSTGRES_USER}') THEN
        raise warning 'Role % already exists', '${HIVEMIND_POSTGRES_USER}';
    ELSE
        CREATE ROLE ${HIVEMIND_POSTGRES_USER}
                WITH LOGIN PASSWORD '${HIVEMIND_POSTGRES_USER_PASSWORD}';
    END IF;
END
\$$;

\echo Creating database ${HIVEMIND_DB_NAME}

CREATE DATABASE ${HIVEMIND_DB_NAME} TEMPLATE template_monitoring
    OWNER ${HIVEMIND_POSTGRES_USER};
COMMENT ON DATABASE ${HIVEMIND_DB_NAME} IS
    'Database for Gitlab CI pipeline ${CI_PIPELINE_URL}, commit ${CI_COMMIT_SHORT_SHA}';

\c ${HIVEMIND_DB_NAME}

create schema hivemind_admin
        authorization ${HIVEMIND_POSTGRES_USER};

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
        OWNER TO ${HIVEMIND_POSTGRES_USER};

alter table hivemind_admin.database_metadata
        OWNER TO ${HIVEMIND_POSTGRES_USER};

insert into hivemind_admin.database_metadata
    (database_name, ci_pipeline_url, ci_pipeline_id, commit_sha)
values (
    '${HIVEMIND_DB_NAME}', '${CI_PIPELINE_URL}',
    ${CI_PIPELINE_ID}, '${CI_COMMIT_SHORT_SHA}'
    );

\q
EOF

}

create_db
