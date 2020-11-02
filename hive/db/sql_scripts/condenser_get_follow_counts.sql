DROP FUNCTION IF EXISTS condenser_get_follow_counts;

CREATE FUNCTION condenser_get_follow_counts( in _account VARCHAR )
RETURNS TABLE(
    following hive_accounts.following%TYPE,
    followers hive_accounts.followers%TYPE
)
AS
$function$
DECLARE
BEGIN

  RETURN QUERY SELECT
    ha.following, ha.followers
    FROM hive_accounts ha
    WHERE ha.name = _account;

END
$function$
language plpgsql STABLE;
