-- Create database

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -f ./create_role_pghero.sql

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';

\echo Creating role pghero

DO
$do$
BEGIN
    IF EXISTS (SELECT * FROM pg_user WHERE pg_user.usename = 'pghero') THEN
        raise warning 'Role % already exists', 'pghero';
    ELSE
        CREATE ROLE pghero WITH LOGIN PASSWORD 'pghero';
        COMMENT ON ROLE pghero IS
            'Role for monitoring https://github.com/ankane/pghero/';
        ALTER ROLE pghero CONNECTION LIMIT 10;
        ALTER ROLE pghero SET search_path = pghero, pg_catalog, public;
        GRANT pg_monitor TO pghero;
   END IF;
END
$do$;
