DROP VIEW IF EXISTS hivemind_app.hive_accounts_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_accounts_view
AS
SELECT ha.id,
  ha.name,
  ha.created_at,
  COALESCE(ar.reputation,0) AS reputation,
  COALESCE(ar.is_implicit, true) as is_implicit,
  ha.followers,
  ha.following,
  ha.rank,
  ha.lastread_at,
  ha.posting_json_metadata,
  ha.json_metadata,
  (COALESCE(ar.reputation,0) <= -464800000000 ) AS is_grayed -- biggest number where rep_log10 gives < 1.0
  FROM hivemind_app.hive_accounts ha
  LEFT JOIN account_reputations ar ON ar.account_id = ha.haf_id --schema needs to be removed to support custom schema
;

