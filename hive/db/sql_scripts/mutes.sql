DROP FUNCTION IF EXISTS mutes_get_blacklisted_for_observer;
CREATE FUNCTION mutes_get_blacklisted_for_observer( in _observer VARCHAR, in _flags INTEGER )
RETURNS TABLE(
    account hive_accounts.name%TYPE,
    source VARCHAR,
    is_blacklisted BOOLEAN -- False means muted
)
AS
$function$
DECLARE
  __observer_id INT;
BEGIN
  __observer_id = find_account_id( _observer, True );
  IF (_flags & 1)::BOOLEAN THEN
    RETURN QUERY SELECT -- mutes_get_blacklisted_for_observer (local observer blacklist)
        ha.name AS account,
        _observer AS source,
        True
    FROM
        hive_follows hf
        JOIN hive_accounts ha ON ha.id = hf.following
    WHERE
        hf.follower = __observer_id AND hf.blacklisted
    ORDER BY account, source;
  END IF;
  IF (_flags & 2)::BOOLEAN THEN
    RETURN QUERY SELECT -- mutes_get_blacklisted_for_observer (indirect observer blacklists)
        ha_i.name AS account,
        ha.name AS source,
        True
    FROM
        hive_follows hf
        JOIN hive_follows hf_i ON hf_i.follower = hf.following
        JOIN hive_accounts ha_i ON ha_i.id = hf_i.following
        JOIN hive_accounts ha ON ha.id = hf.following
    WHERE
        hf.follower = __observer_id AND hf.follow_blacklists AND hf_i.blacklisted
    ORDER BY account, source;
  END IF;
  IF (_flags & 4)::BOOLEAN THEN
    RETURN QUERY SELECT-- mutes_get_blacklisted_for_observer (local observer mute list)
        ha.name AS account,
        _observer AS source,
        False
    FROM
        hive_follows hf
        JOIN hive_accounts ha ON ha.id = hf.following
    WHERE
        hf.follower = __observer_id AND hf.state = 2
    ORDER BY account, source;
  END IF;
  IF (_flags & 8)::BOOLEAN THEN
    RETURN QUERY SELECT-- mutes_get_blacklisted_for_observer (indirect observer mute list)
        ha_i.name AS account,
        ha.name AS source,
        False
    FROM
        hive_follows hf
        JOIN hive_follows hf_i ON hf_i.follower = hf.following
        JOIN hive_accounts ha_i ON ha_i.id = hf_i.following
        JOIN hive_accounts ha ON ha.id = hf.following
    WHERE
        hf.follower = __observer_id AND hf.follow_muted AND hf_i.state = 2
    ORDER BY account, source;
  END IF;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS mutes_get_blacklists_for_observer;
CREATE FUNCTION mutes_get_blacklists_for_observer( in _observer VARCHAR, in _follow_blacklist BOOLEAN, in _follow_muted BOOLEAN )
RETURNS TABLE(
    list hive_accounts.name%TYPE,
    is_blacklist BOOLEAN -- False means mute list
)
AS
$function$
DECLARE
  __observer_id INT;
BEGIN
  __observer_id = find_account_id( _observer, True );
  IF _follow_blacklist THEN
    RETURN QUERY SELECT -- mutes_get_blacklists_for_observer (observer blacklists)
        ha.name AS list,
        True
    FROM
        hive_follows hf
        JOIN hive_accounts ha ON ha.id = hf.following
    WHERE
        hf.follower = __observer_id AND hf.follow_blacklists
    ORDER BY list;
  END IF;
  IF _follow_muted THEN
    RETURN QUERY SELECT -- mutes_get_blacklists_for_observer (observer mute lists)
        ha.name AS list,
        False
    FROM
        hive_follows hf
        JOIN hive_accounts ha ON ha.id = hf.following
    WHERE
        hf.follower = __observer_id AND hf.follow_muted
    ORDER BY list;
  END IF;
END
$function$
language plpgsql STABLE;
