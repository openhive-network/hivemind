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

DROP FUNCTION IF EXISTS condenser_get_followers;
-- list of account names that follow/ignore given account
CREATE FUNCTION condenser_get_followers( in _account VARCHAR, in _start VARCHAR, in _type INT, in _limit INT )
RETURNS SETOF hive_accounts.name%TYPE
AS
$function$
DECLARE
  __account_id INT;
  __start_id INT;
BEGIN
  __account_id = find_account_id( _account, True );
  __start_id = find_account_id( _start, _start <> '' );
  IF __start_id <> 0 THEN
      SELECT INTO __start_id COALESCE( ( SELECT id FROM hive_follows WHERE following = __account_id AND follower = __start_id ), 0 );
  END IF;
  RETURN QUERY SELECT
     ha.name
  FROM
     hive_follows hf
     JOIN hive_accounts ha ON hf.follower = ha.id
  WHERE
     hf.following = __account_id AND hf.state = _type AND ( __start_id = 0 OR hf.id < __start_id )
  ORDER BY hf.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS condenser_get_following;
-- list of account names followed/ignored by given account
CREATE FUNCTION condenser_get_following( in _account VARCHAR, in _start VARCHAR, in _type INT, in _limit INT )
RETURNS SETOF hive_accounts.name%TYPE
AS
$function$
DECLARE
  __account_id INT;
  __start_id INT;
BEGIN
  __account_id = find_account_id( _account, True );
  __start_id = find_account_id( _start, _start <> '' );
  IF __start_id <> 0 THEN
      SELECT INTO __start_id COALESCE( ( SELECT id FROM hive_follows WHERE follower = __account_id AND following = __start_id ), 0 );
  END IF;
  RETURN QUERY SELECT
     ha.name
  FROM
     hive_follows hf
     JOIN hive_accounts ha ON hf.following = ha.id
  WHERE
     hf.follower = __account_id AND hf.state = _type AND ( __start_id = 0 OR hf.id < __start_id )
  ORDER BY hf.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
