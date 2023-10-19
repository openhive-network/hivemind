-- Create database

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -f ./create_template.sql --set=db_name=template_monitoring

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';

-- Handle default values for variables.
\set db_name ':db_name'
-- now db_name is set to the string ':db_name' if was not already set.
-- Checking it using a CASE statement:
SELECT CASE
  WHEN :'db_name'= ':db_name'
  THEN 'template_monitoring'
  ELSE :'db_name'
END AS "db_name"
\gset

\echo Creating database :db_name

CREATE DATABASE :db_name;
COMMENT ON DATABASE :db_name IS 'Template for monitoring';
