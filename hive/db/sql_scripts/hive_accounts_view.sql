DROP FUNCTION IF EXISTS hivemind_app.convert_haf_id CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.convert_haf_id(IN _account_id INT)
  RETURNS INT
  LANGUAGE 'plpgsql'
  IMMUTABLE
AS $BODY$
BEGIN
RETURN _account_id + 1;
END
$BODY$;
--slower than hive.accounts_view join


DROP VIEW IF EXISTS hivemind_app.hive_account_reputations_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_account_reputations_view
AS
SELECT 
  av.name,
  COALESCE(ar.reputation,0) AS reputation,
  COALESCE(ar.is_implicit, true) as is_implicit,
  (COALESCE(ar.reputation,0) <= -464800000000 ) AS is_grayed -- biggest number where rep_log10 gives < 1.0
  FROM reptracker_app.accounts_view av  --schema needs to be removed to support custom schema
  LEFT JOIN reptracker_app.account_reputations ar ON ar.account_id = av.id --schema needs to be removed to support custom schema
  ;
  
--hive_accounts id is hive.accounts id + 1 BUT when mocks are created the additional 
--accounts are being pushed to hive_accounts but haf's tables stays the same (20 accounts that changes the order of ids).
--Because of this fact the hivemind_app.convert_haf_id does work on normal instance 
--but it doesn't for CI instance supplied with mocks and hive_accounts_view requires join on haf accounts to find universal account id
--schema name should be removed once the python server will be rewritten to sql and postgrest server


DROP VIEW IF EXISTS hivemind_app.hive_accounts_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_accounts_view
AS
SELECT ha.id,
  ha.name,
  ha.created_at,
  har.reputation,
  har.is_implicit,
  ha.followers,
  ha.following,
  ha.rank,
  ha.lastread_at,
  ha.posting_json_metadata,
  ha.json_metadata,
  har.is_grayed -- biggest number where rep_log10 gives < 1.0
  FROM hivemind_app.hive_accounts ha
  JOIN hivemind_app.hive_account_reputations_view har ON har.name = ha.name --schema needs to be removed to support custom schema
  ;
