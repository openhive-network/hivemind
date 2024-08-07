DROP FUNCTION IF EXISTS hivemind_app.get_followers;
CREATE OR REPLACE FUNCTION hivemind_app.get_followers(
    in "account" VARCHAR(50),
    in "start" TEXT DEFAULT NULL,
    in "type" VARCHAR(10),
    in "limit" INT,
)
AS
$BODY$
DECLARE
__account VARCHAR(50) = hivemind_helpers.valid_account(account, allow_empty=TRUE)
__start TEXT DEFAULT NULL =
__type VARCHAR(10) = hivemind_helpers.valid_follow_type(type)
__limit INT = hivemind_helpers.valid_limit(_limit,1000,1000);

BEGIN
  RETURN (role, subscribed, title)::hivemind_helpers.community_context
  FROM json_to_record(SELECT * FROM hivemind_app.condenser_get_followers(account, "start", "type", "limit"))

  SELECT * FROM hivemind_app.condenser_get_followers( (:account)::VARCHAR, (:start)::VARCHAR, :type, :limit )
;
