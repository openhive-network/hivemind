DROP FUNCTION IF EXISTS condenser_get_names_by_following;

CREATE FUNCTION condenser_get_names_by_following( in _account VARCHAR, in _start_account VARCHAR, in _state SMALLINT, _limit SMALLINT )
RETURNS TABLE(
    names hive_accounts.name%TYPE
)
AS
$function$
DECLARE
  __account_id INT := find_account_id( _account, True );
  __start_account_id INT := 0;
  __created_at TIMESTAMP;
BEGIN

  IF _start_account <> '' THEN
    __start_account_id = find_account_id( _start_account, True );
  END IF;

  IF __start_account_id <> 0 THEN
    SELECT hf.created_at
    INTO __created_at
    FROM hive_follows hf
    WHERE hf.follower = __account_id AND hf.following = __start_account_id;
  END IF;

  RETURN QUERY SELECT
    name
  FROM hive_follows hf
  LEFT JOIN hive_accounts ha ON hf.following = ha.id
  WHERE hf.follower = __account_id
  AND state = _state
  AND ( __start_account_id = 0 OR hf.created_at <= __created_at )
  ORDER BY hf.created_at DESC
  LIMIT _limit;

END
$function$
language plpgsql STABLE;
