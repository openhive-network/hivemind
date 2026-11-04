DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_followers;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_followers(IN _params JSONB, IN _called_from_condenser_api BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _start TEXT DEFAULT '';
  _account_id INT;
  _state SMALLINT;
  _limit INT;
  _followers FLOAT8;
  _accounts FLOAT8;
  _walk_budget FLOAT8;
  _name TEXT;
  _names TEXT[] DEFAULT '{}';
BEGIN
  _params = hivemind_postgrest_utilities.extract_parameters_for_get_following_and_followers(_params, _called_from_condenser_api);
  _account_id = (_params->'account_id')::INT;
  _limit = (_params->'limit')::INT;
  _start = (_params->>'start')::TEXT;

  -- For a small page of a heavily followed account, walk hive_accounts_ux1 by name and probe follows_pkey
  -- instead of reading and sorting every follower. Assuming followers spread evenly over names, a page takes
  -- about _limit * accounts / followers probes; the walk stops at twice that and falls back to the query
  -- below when followers cluster elsewhere, which bounds a misjudged walk to about the follower count.
  IF (_params->'follows')::boolean THEN
    SELECT ha.followers INTO _followers FROM hivemind_app.hive_accounts AS ha WHERE ha.id = _account_id;
    SELECT GREATEST(c.reltuples, 1) INTO _accounts FROM pg_class AS c WHERE c.oid = 'hivemind_app.hive_accounts'::regclass;
    _walk_budget = 2 * _limit * _accounts / NULLIF(_followers, 0);

    IF _walk_budget < _followers THEN
      -- A FOR loop's query is planned without parallelism: a Gather Merge over the walk makes every
      -- worker walk until it alone has filled the page.
      FOR _name IN
        SELECT w.name
        FROM (
          SELECT ha.id, ha.name
          FROM hivemind_app.hive_accounts AS ha
          WHERE ha.name >= _start AND (_start = '' OR ha.name <> _start)
          ORDER BY ha.name
          LIMIT ceil(_walk_budget)::BIGINT
        ) AS w
        WHERE EXISTS (SELECT NULL FROM hivemind_app.follows AS f WHERE f.follower = w.id AND f.following = _account_id)
        ORDER BY w.name
        LIMIT _limit
      LOOP
        _names = array_append(_names, _name);
      END LOOP;

      IF cardinality(_names) = _limit THEN
        RETURN (
          SELECT jsonb_agg( -- condenser_api_get_followers (walk)
            jsonb_build_object(
              'following', _params->'account',
              'follower', n.name,
              'what', jsonb_build_array(_params->'follow_type')
            )
            ORDER BY n.position
          )
          FROM unnest(_names) WITH ORDINALITY AS n(name, position)
        );
      END IF;
    END IF;
  END IF;

  RETURN COALESCE(
  (
    SELECT jsonb_agg( -- condenser_api_get_followers
      jsonb_build_object(
        'following', _params->'account',
        'follower', row.name,
        'what', jsonb_build_array(_params->'follow_type')
      )
      ORDER BY row.name
    )
    FROM (
      WITH followers AS MATERIALIZED
        (
        SELECT ha.name
        FROM hivemind_app.follows AS f
        JOIN hivemind_app.hive_accounts AS ha ON f.follower = ha.id
        WHERE f.following = _account_id
              AND (_start = '' OR ha.name > _start)
              AND (_params->'follows')::boolean
        UNION ALL
        SELECT ha.name
        FROM hivemind_app.muted AS m
        JOIN hivemind_app.hive_accounts AS ha ON m.follower = ha.id
        WHERE m.following = _account_id
              AND (_start = '' OR ha.name > _start)
              AND (_params->'mutes')::boolean
        ORDER BY name
        LIMIT _limit
        )
      SELECT name
      FROM followers
      ORDER BY name
      LIMIT _limit
    ) row
  ),
  '[]'::jsonb
  );
END
$$
;

