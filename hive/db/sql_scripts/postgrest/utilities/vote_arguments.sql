DROP TYPE IF EXISTS hivemind_postgrest_utilities.vote_arguments CASCADE;
CREATE TYPE hivemind_postgrest_utilities.vote_arguments AS (
  author TEXT,
  permlink TEXT
);