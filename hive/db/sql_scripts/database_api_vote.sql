DROP TYPE IF EXISTS database_api_vote CASCADE;

CREATE TYPE database_api_vote AS (
  voter VARCHAR(16),
  author VARCHAR(16),
  permlink VARCHAR(255),
  weight NUMERIC,
  rshares BIGINT,
  percent INT,
  last_update TIMESTAMP,
  num_changes INT,
  reputation FLOAT4
);