DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_follow_count;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_follow_count(IN _account TEXT)
RETURNS JSON
LANGUAGE 'plpgsql'
AS
$$
DECLARE
  _account_id INT;
BEGIN
  _account_id = hivemind_utilities.find_account_id(hivemind_utilities.valid_account(_account, False), True);
  RETURN (
    SELECT to_json(row) FROM (
      SELECT name AS account, ha.following AS following_count, ha.followers AS follower_count FROM hivemind_app.hive_accounts ha WHERE ha.id = _account_id
    ) row );
END;
$$
;