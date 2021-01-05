-- Create database

-- Example run:
-- psql -p 5432 -U postgres -h 127.0.0.1 -f ./setup_template.sql --set=db_name=template_monitoring

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

update pg_database
    set
        datistemplate = true,
        datallowconn = false
    where datname = :'db_name';
