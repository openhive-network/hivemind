DROP FUNCTION IF EXISTS hivemind_app.bridge_get_relationship_between_accounts;

CREATE FUNCTION hivemind_app.bridge_get_relationship_between_accounts( in _account1 VARCHAR, in _account2 VARCHAR,
  out follows BOOLEAN,
  out muted BOOLEAN,
  out blacklisted BOOLEAN,
  out follow_blacklists BOOLEAN,
  out follow_muted BOOLEAN)
AS
$function$
DECLARE
  __account1_id INT;
  __account2_id INT;
BEGIN
  __account1_id = hivemind_app.find_account_id( _account1, True );
  __account2_id = hivemind_app.find_account_id( _account2, True );

  SELECT EXISTS (SELECT 1 FROM hivemind_app.follows WHERE follower=__account1_id  AND FOLLOWING=__account2_id) INTO follows;
  SELECT EXISTS (SELECT 1 FROM hivemind_app.muted WHERE follower=__account1_id  AND FOLLOWING=__account2_id) INTO muted;
  SELECT EXISTS (SELECT 1 FROM hivemind_app.blacklisted WHERE follower=__account1_id  AND FOLLOWING=__account2_id) INTO blacklisted;
  SELECT EXISTS (SELECT 1 FROM hivemind_app.follow_blacklisted WHERE follower=__account1_id  AND FOLLOWING=__account2_id) INTO follow_blacklists;
  SELECT EXISTS (SELECT 1 FROM hivemind_app.follow_muted WHERE follower=__account1_id  AND FOLLOWING=__account2_id) INTO follow_muted;
END
$function$
language plpgsql STABLE;
