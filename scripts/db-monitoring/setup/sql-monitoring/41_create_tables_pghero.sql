-- Create database

-- Creates tables for gathering historical stats data. You need them in pghero
-- database only.
-- Example run:
-- psql postgresql://pghero:pghero@127.0.0.1:5432/pghero -f ./create_tables_pghero.sql

SET client_encoding = 'UTF8';
SET client_min_messages = 'warning';

\echo Creating tables in database pghero

\c pghero pghero

BEGIN;

CREATE SCHEMA pghero;

CREATE TABLE "pghero"."pghero_query_stats" (
  "id" bigserial primary key,
  "database" text,
  "user" text,
  "query" text,
  "query_hash" bigint,
  "total_time" float,
  "calls" bigint,
  "captured_at" timestamp
);
CREATE INDEX ON "pghero"."pghero_query_stats" ("database", "captured_at");

CREATE TABLE "pghero_space_stats" (
  "id" bigserial primary key,
  "database" text,
  "schema" text,
  "relation" text,
  "size" bigint,
  "captured_at" timestamp
);
CREATE INDEX ON "pghero_space_stats" ("database", "captured_at");

COMMIT;
