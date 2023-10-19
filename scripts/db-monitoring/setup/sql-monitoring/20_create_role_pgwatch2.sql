-- Create database

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -f ./create_role_pgwatch2.sql

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';

\echo Creating role pgwatch2

DO
$do$
BEGIN
    IF EXISTS (SELECT * FROM pg_user WHERE pg_user.usename = 'pgwatch2') THEN
        raise warning 'Role % already exists', 'pgwatch2';
    ELSE
        -- NB! For critical databases it might make sense to ensure that the user account
        -- used for monitoring can only open a limited number of connections
        -- (there are according checks in code, but multiple instances might be launched)
        CREATE ROLE pgwatch2 WITH LOGIN PASSWORD 'pgwatch2';
        COMMENT ON ROLE pgwatch2 IS
            'Role for monitoring https://github.com/cybertec-postgresql/pgwatch2';
        ALTER ROLE pgwatch2 CONNECTION LIMIT 10;
        GRANT pg_monitor TO pgwatch2;
   END IF;
END
$do$;
