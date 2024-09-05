DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_account_reputations;
-- this _fat_node_style is true for condenser api and false for follow api at the moment
CREATE OR REPLACE FUNCTION hivemind_endpoints.condenser_api_get_account_reputations(IN _account_lower_bound TEXT, IN _limit INTEGER, IN _fat_node_style BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
AS
$$
BEGIN
  _limit = hivemind_utilities.valid_number(_limit, 1000, 1, 1000, 'limit');
  IF _account_lower_bound IS NULL THEN
    _account_lower_bound = '';
  END IF;

  IF _fat_node_style THEN
    RETURN (
      SELECT to_json(result.array) FROM (
        SELECT ARRAY (
          SELECT to_json(row) FROM (
            SELECT ha.name AS account, ha.reputation AS reputation
              FROM hivemind_app.hive_accounts_view ha
              WHERE ha.name >= _account_lower_bound AND ha.id != 0
              ORDER BY ha.name
              LIMIT _limit
          ) row
        )
      ) result
    );
  ELSE
    RETURN json_build_object('reputations', (
      SELECT to_json(result.array) FROM (
        SELECT ARRAY (
          SELECT to_json(row) FROM (
            SELECT ha.name AS name, ha.reputation AS reputation
              FROM hivemind_app.hive_accounts_view ha
              WHERE ha.name >= _account_lower_bound AND ha.id != 0
              ORDER BY ha.name
              LIMIT _limit
          ) row
        )
      ) result
    ));
  END IF;
END;
$$
;