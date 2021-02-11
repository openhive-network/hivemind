DROP FUNCTION IF EXISTS bridge_get_relationship_between_accounts;

CREATE FUNCTION bridge_get_relationship_between_accounts( in _account1 VARCHAR, in _account2 VARCHAR,
  out state hive_follows.state%TYPE,
  out blacklisted hive_follows.blacklisted%TYPE,
  out follow_blacklists hive_follows.follow_blacklists%TYPE,
  out follow_muted hive_follows.follow_muted%TYPE,
  out id hive_follows.id%TYPE,
  out created_at hive_follows.created_at%TYPE,
  out block_num hive_follows.block_num%TYPE)
AS
$function$
DECLARE
  __account1_id INT;
  __account2_id INT;
BEGIN
  __account1_id = find_account_id( _account1, True );
  __account2_id = find_account_id( _account2, True );
  SELECT
      hf.state,
      hf.blacklisted,
      hf.follow_blacklists,
      hf.follow_muted,
      hf.id,
      hf.created_at,
      hf.block_num
  INTO
      state,
      blacklisted,
      follow_blacklists,
      follow_muted,
      id,
      created_at,
      block_num
  FROM
      hive_follows hf
  WHERE
      hf.follower = __account1_id AND hf.following = __account2_id;
END
$function$
language plpgsql STABLE;
