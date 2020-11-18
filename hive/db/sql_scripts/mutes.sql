DROP FUNCTION IF EXISTS mutes_get_blacklists_for_observer;
CREATE FUNCTION mutes_get_blacklists_for_observer( in _observer VARCHAR )
RETURNS TABLE(
    account hive_accounts.name%TYPE,
    source VARCHAR
)
AS
$function$
DECLARE
  __observer_id INT;
BEGIN
  __observer_id = find_account_id( _observer, True );
  RETURN QUERY SELECT -- mutes_get_blacklists_for_observer (local observer blacklist)
      ha.name AS account,
      _observer AS source
  FROM
      hive_follows hf
      JOIN hive_accounts ha ON ha.id = hf.following
  WHERE
      hf.follower = __observer_id AND hf.blacklisted;
  RETURN QUERY SELECT -- mutes_get_blacklists_for_observer (indirect observer blacklists)
      ha_i.name AS account,
      ha.name AS source
  FROM
      hive_follows hf
      JOIN hive_follows hf_i ON hf_i.follower = hf.following
      JOIN hive_accounts ha_i ON ha_i.id = hf_i.following
      JOIN hive_accounts ha ON ha.id = hf.following
  WHERE
      hf.follower = __observer_id AND hf.follow_blacklists AND hf_i.blacklisted;
  RETURN QUERY SELECT-- mutes_get_blacklists_for_observer (local observer mute list)
      ha.name AS account,
      CONCAT( _observer, ' (mute list)' )::VARCHAR AS source
  FROM
      hive_follows hf
      JOIN hive_accounts ha ON ha.id = hf.following
  WHERE
      hf.follower = __observer_id AND hf.state = 2;
  RETURN QUERY SELECT-- mutes_get_blacklists_for_observer (indirect observer mute list)
      ha_i.name AS account,
      CONCAT( ha.name, ' (mute list)' )::VARCHAR AS source
  FROM
      hive_follows hf
      JOIN hive_follows hf_i ON hf_i.follower = hf.following
      JOIN hive_accounts ha_i ON ha_i.id = hf_i.following
      JOIN hive_accounts ha ON ha.id = hf.following
  WHERE
      hf.follower = __observer_id AND hf.follow_muted AND hf_i.state = 2;
END
$function$
language plpgsql STABLE;
