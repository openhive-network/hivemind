-- Create database

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -f ./create_database.sql --set=db_name=template_hive_ci

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';

CREATE DATABASE :db_name;
CREATE EXTENSION intarray SCHEMA public;