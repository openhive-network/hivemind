DROP FUNCTION IF EXISTS condenser_get_follow_count;
CREATE FUNCTION condenser_get_follow_count( in _account VARCHAR,
  out following hive_accounts.following%TYPE, out followers hive_accounts.followers%TYPE )
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = find_account_id( _account, True );
  SELECT ha.following, ha.followers INTO following, followers FROM hive_accounts ha WHERE ha.id = __account_id;
  -- following equals (SELECT COUNT(*) FROM hive_follows WHERE state = 1 AND following = __account_id)
  -- followers equals (SELECT COUNT(*) FROM hive_follows WHERE state = 1 AND follower  = __account_id)
END
$function$
language plpgsql STABLE;
