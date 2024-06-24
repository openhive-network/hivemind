DROP FUNCTION IF EXISTS hivemind_app.condenser_get_account_reputations;

CREATE OR REPLACE FUNCTION hivemind_app.condenser_get_account_reputations(
  in _account_lower_bound VARCHAR,
  in _limit INTEGER
)
RETURNS TABLE
(
    name hivemind_app.hive_accounts.name%TYPE,
    reputation BIGINT
)
AS
$function$
DECLARE

BEGIN

    RETURN QUERY SELECT
      ha.name, ha.reputation
    FROM hivemind_app.hive_accounts_view ha
    WHERE ha.name >= _account_lower_bound AND ha.id != 0 -- don't include artificial empty account
    ORDER BY name
    LIMIT _limit;

END
$function$
language plpgsql STABLE;
