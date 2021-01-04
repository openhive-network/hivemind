DROP FUNCTION IF EXISTS condenser_get_account_reputations;

CREATE OR REPLACE FUNCTION condenser_get_account_reputations(
  in _account_lower_bound VARCHAR,
  in _limit INTEGER
)
RETURNS TABLE
(
    name hive_accounts.name%TYPE,
    reputation hive_accounts.reputation%TYPE
)
AS
$function$
DECLARE

BEGIN

    RETURN QUERY SELECT
      ha.name, ha.reputation
    FROM hive_accounts ha
    WHERE ha.name >= _account_lower_bound AND ha.id != 0 -- don't include artificial empty account
    ORDER BY name
    LIMIT _limit;

END
$function$
language plpgsql STABLE;
