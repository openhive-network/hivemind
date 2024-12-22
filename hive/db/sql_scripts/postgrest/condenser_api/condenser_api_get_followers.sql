DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_followers;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_followers(
  IN _params JSONB,
  IN _called_from_condenser_api BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$$
DECLARE
  -- Raw fields from JSON
  _account          TEXT;
  _start            TEXT;
  _follow_type      TEXT;
  _limit_val        INT;

  -- Derived states
  _account_id       INT;
  _start_id         INT DEFAULT 2147483647;  -- default to max INT if we cannot find something
  _hive_follows_state SMALLINT;
BEGIN
  ---------------------------------------------------------------------------
  -- 1. Handle NULL or unexpected _params
  ---------------------------------------------------------------------------
  IF _params IS NULL THEN
    RAISE EXCEPTION 'Missing JSON-RPC _params';
  END IF;

  ---------------------------------------------------------------------------
  -- 2. Distinguish between object vs. array
  --    If array of length=1 and element is an object, treat that as our params object
  ---------------------------------------------------------------------------
  IF jsonb_typeof(_params) = 'array'
     AND jsonb_array_length(_params) = 1
     AND jsonb_typeof(_params->0) = 'object'
  THEN
    _params := _params->0;  -- unwrap the single-object array
  ELSIF jsonb_typeof(_params) = 'array' THEN
    -- Possibly positional arguments from old JSON-RPC calls?
    -- If so, define the positions: [account, start, follow_type (or type), limit]
    -- For demonstration, we’ll do minimal checks:
    IF jsonb_array_length(_params) < 1 THEN
      RAISE EXCEPTION 'Missing required "account" in positional arguments';
    END IF;
    _account := _params->>0;

    IF jsonb_array_length(_params) >= 2 THEN
      _start := _params->>1;
    END IF;
    IF jsonb_array_length(_params) >= 3 THEN
      -- Could be "follow_type" or "type" depending on _called_from_condenser_api
      IF _called_from_condenser_api THEN
        _follow_type := _params->>2;
      ELSE
        -- If not condenser, that field name might be "type"
        _follow_type := _params->>2;
      END IF;
    END IF;
    IF jsonb_array_length(_params) >= 4 THEN
      _limit_val := (_params->>3)::INT;
    END IF;
  ELSIF jsonb_typeof(_params) = 'object' THEN
    -- Named parameters
    _account := _params->>'account';
    _start   := _params->>'start';

    IF _called_from_condenser_api THEN
      _follow_type := _params->>'follow_type';  -- e.g. "blog" or "ignore"
    ELSE
      _follow_type := _params->>'type';
    END IF;

    _limit_val := COALESCE(( _params->>'limit' )::INT, 0);
  ELSE
    RAISE EXCEPTION 'Invalid _params format: expected object or array';
  END IF;

  ---------------------------------------------------------------------------
  -- 3. Fallbacks and minimal validations
  ---------------------------------------------------------------------------
  IF _account IS NULL OR _account = '' THEN
    RAISE EXCEPTION 'Missing or empty "account" parameter';
  END IF;

  -- Default follow type if missing
  IF (_follow_type IS NULL) OR (_follow_type = '') THEN
    _follow_type := 'blog';
  END IF;

  IF _follow_type = 'blog' THEN
    _hive_follows_state := 1;
  ELSIF _follow_type = 'ignore' THEN
    _hive_follows_state := 2;
  ELSE
    RAISE EXCEPTION 'Unsupported follow type (allowed: blog, ignore)';
  END IF;

  -- Default limit if missing or zero
  IF _limit_val IS NULL OR _limit_val < 1 OR _limit_val > 1000 THEN
    _limit_val := 1000;
  END IF;

  ---------------------------------------------------------------------------
  -- 4. Convert names to IDs
  --    (still calling your existing "valid_account" + "find_account_id" is fine)
  ---------------------------------------------------------------------------
  _account_id := hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_account, False),
    True
  );

  IF _start IS NOT NULL AND _start <> '' THEN
    _start_id := hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(_start, True),
      True
    );

    -- If _start_id = 0, we do not modify the default _start_id above.
    IF _start_id = 0 THEN
      _start_id := 2147483647;
    END IF;
  END IF;

  ---------------------------------------------------------------------------
  -- 5. If the user passed a non-zero "start" account, override _start_id from hive_follows
  ---------------------------------------------------------------------------
  IF _start_id <> 2147483647 THEN
    -- The older code checked the "start" with a separate query:
    --   SELECT hf.id
    --   FROM hive_follows hf
    --   WHERE hf.following = _account_id
    --         AND hf.follower = that "start" ID
    -- to re-assign _start_id
    --
    SELECT hf.id
      INTO _start_id
      FROM hivemind_app.hive_follows hf
     WHERE hf.following = _account_id
       AND hf.follower  = _start_id
     LIMIT 1;  -- If no row found, it remains NULL and won't break next logic
    IF NOT FOUND THEN
      -- If not found, you might want to revert to 2147483647 or keep it as NULL
      _start_id := 2147483647;
    END IF;
  END IF;

  ---------------------------------------------------------------------------
  -- 6. Final query: same as original
  ---------------------------------------------------------------------------
  RETURN COALESCE(
    (
      SELECT jsonb_agg(
               jsonb_build_object(
                 'following', _account,  -- the one we are looking up
                 'follower', row.name,   -- each row's name
                 'what', jsonb_build_array(_follow_type)
               )
               ORDER BY row.id DESC
             )
      FROM (
        WITH followers AS MATERIALIZED (
          SELECT
            hf.id,
            hf.follower
          FROM hivemind_app.hive_follows hf
          WHERE hf.following = _account_id
            AND hf.state     = _hive_follows_state  -- blog=1 or ignore=2
            AND hf.id        < _start_id
          ORDER BY hf.id DESC
          LIMIT _limit_val
        )
        SELECT
          followers.id,
          ha.name
        FROM followers
        JOIN hivemind_app.hive_accounts ha ON followers.follower = ha.id
        ORDER BY followers.id DESC
        LIMIT _limit_val
      ) row
    ),
    '[]'::jsonb
  );
END
$$
;

