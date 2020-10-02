DROP FUNCTION IF EXISTS bridge_get_relationship_between_accounts;

CREATE FUNCTION bridge_get_relationship_between_accounts( in _account1 VARCHAR, in _account2 VARCHAR )
RETURNS TABLE(
    state hive_follows.state%TYPE,
    blacklisted hive_follows.blacklisted%TYPE,
    follow_blacklists hive_follows.follow_blacklists%TYPE
)
AS
$function$
DECLARE
  __account1_id INT;
  __account2_id INT;
BEGIN
  __account1_id = find_account_id( _account1, True );
  __account2_id = find_account_id( _account2, True );
  RETURN QUERY SELECT
      hf.state,
      hf.blacklisted,
      hf.follow_blacklists
  FROM
      hive_follows hf
  WHERE
      hf.follower = __account1_id AND hf.following = __account2_id;
END
$function$
language plpgsql STABLE;
