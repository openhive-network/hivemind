DROP VIEW IF EXISTS hivemind_app.hive_accounts_view CASCADE;

CREATE OR REPLACE VIEW hivemind_app.hive_accounts_view
AS
SELECT id,
  name,
  created_at,
  reputation,
  is_implicit,
  followers,
  following,
  rank,
  lastread_at,
  posting_json_metadata,
  json_metadata,
  ( reputation <= -464800000000 ) is_grayed -- biggest number where rep_log10 gives < 1.0
  FROM hivemind_app.hive_accounts
  ;
