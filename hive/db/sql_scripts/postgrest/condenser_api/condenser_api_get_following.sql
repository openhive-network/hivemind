DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_following;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_following(
  IN _params JSONB,
  IN _called_from_condenser_api BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$$
DECLARE
  _account            TEXT;
  _start              TEXT;
  _follow_type        TEXT;
  _limit_val          INT;
  
  _account_id         INT;
  _start_id           INT DEFAULT 0;
  _hive_follows_state SMALLINT;
BEGIN
  ---------------------------------------------------------------------------
  -- 1. Handle NULL or unexpected _params
  ---------------------------------------------------------------------------
  IF _params IS NULL THEN
    RAISE EXCEPTION 'Missing JSON-RPC _params';
  END IF;

  ---------------------------------------------------------------------------
  -- 2. Check array vs object. Unwrap if single-object array
  ---------------------------------------------------------------------------
  IF jsonb_typeof(_params) = 'array'
     AND jsonb_array_length(_params) = 1
     AND jsonb_typeof(_params->0) = 'object'
  THEN
    _params := _params->0;  -- unwrap single-object array
  ELSIF jsonb_typeof(_params) = 'array' THEN
    -- Possibly positional [account, start, follow_type or type, limit]
    IF jsonb_array_length(_params) < 1 THEN
      RAISE EXCEPTION 'Missing "account" in positional params';
    END IF;
    _account := _params->>0;
    
    IF jsonb_array_length(_params) >= 2 THEN
      _start := _params->>1;
    END IF;
    IF jsonb_array_length(_params) >= 3 THEN
      IF _called_from_condenser_api THEN
        _follow_type := _params->>2;
      ELSE
        _follow_type := _params->>2;
      END IF;
    END IF;
    IF jsonb_array_length(_params) >= 4 THEN
      _limit_val := (_params->>3)::INT;
    END IF;
  ELSIF jsonb_typeof(_params) = 'object' THEN
    _account := _params->>'account';
    _start   := _params->>'start';
    IF _called_from_condenser_api THEN
      _follow_type := _params->>'follow_type';
    ELSE
      _follow_type := _params->>'type';
    END IF;
    _limit_val := COALESCE((_params->>'limit')::INT, 0);
  ELSE
    RAISE EXCEPTION 'Invalid _params format: expected object or array';
  END IF;

  ---------------------------------------------------------------------------
  -- 3. Minimal validation and defaults
  ---------------------------------------------------------------------------
  IF _account IS NULL OR _account = '' THEN
    RAISE EXCEPTION 'Missing or empty "account" parameter';
  END IF;

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

  IF _limit_val IS NULL OR _limit_val < 1 OR _limit_val > 1000 THEN
    _limit_val := 1000;
  END IF;

  ---------------------------------------------------------------------------
  -- 4. Convert to IDs
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
    -- If no match, it remains 0
  END IF;

  ---------------------------------------------------------------------------
  -- 5. If we found a start user, possibly refine _start_id with a hive_follows lookup
  ---------------------------------------------------------------------------
  IF _start_id <> 0 THEN
    SELECT hf.id
      INTO _start_id
      FROM hivemind_app.hive_follows hf
     WHERE hf.follower  = _account_id
       AND hf.following = _start_id
     LIMIT 1;

    -- If not found, keep it 0 so the query uses the top
    IF NOT FOUND THEN
      _start_id := 0;
    END IF;
  END IF;

  ---------------------------------------------------------------------------
  -- 6. Final query: same as original
  ---------------------------------------------------------------------------
  RETURN COALESCE(
    (
      SELECT jsonb_agg(
               jsonb_build_object(
                 'following', row.name,
                 'follower', _account,
                 'what', jsonb_build_array(_follow_type)
               )
               ORDER BY row.id DESC
             )
      FROM (
        WITH max_10k_following AS (
          SELECT
            hf.id,
            hf.following
          FROM hivemind_app.hive_follows hf
          WHERE hf.state    = _hive_follows_state
            AND hf.follower = _account_id
          LIMIT 10000  -- if user follows more than 10K accounts, limit them
        ),
        following_page AS (
          SELECT
            hf.id,
            hf.following
          FROM max_10k_following hf
          WHERE (_start_id = 0 OR hf.id < _start_id)
          ORDER BY hf.id DESC
          LIMIT _limit_val
        )
        SELECT
          fs.id,
          ha.name
        FROM following_page fs
        JOIN hivemind_app.hive_accounts ha ON fs.following = ha.id
        ORDER BY fs.id DESC
        LIMIT _limit_val
      ) row
    ),
    '[]'::jsonb
  );
END
$$
;

