-- Create database

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -f ./create_database_pghero.sql

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';

\echo Creating database pghero

CREATE DATABASE pghero OWNER pghero;
COMMENT ON DATABASE pghero
    IS 'Historical data for monitoring https://github.com/ankane/pghero/'