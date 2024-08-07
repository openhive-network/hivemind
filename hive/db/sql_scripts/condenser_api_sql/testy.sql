DROP FUNCTION IF EXISTS hivemind_helpers.get_community_context;
CREATE OR REPLACE FUNCTION hivemind_helpers.get_community_context(
  IN account TEXT DEFAULT NULL,
  IN "start" TEXT,
  IN "type" TEXT,
  IN "limit" TEXT
)
  RETURNS SETOF hivemind_helpers.community_context
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _name TEXT = hivemind_helpers.valid_community(name);
  _account TEXT = hivemind_helpers.valid_account(account);

BEGIN
  RETURN (role, subscribed, title)::hivemind_helpers.community_context
  FROM json_to_record(SELECT * FROM hivemind_app.condenser_get_followers(account, "start", "type", "limit"))
;


END;
$BODY$o
;