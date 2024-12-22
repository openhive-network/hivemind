DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_follow_count;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_follow_count(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _account_id INT;
BEGIN
  ---------------------------------------------------------------------------
  -- 1. Handle NULL or unexpected input
  ---------------------------------------------------------------------------
  IF _params IS NULL THEN
    RAISE EXCEPTION 'Missing JSON-RPC _params';
  END IF;

  ---------------------------------------------------------------------------
  -- 2. Distinguish between object vs. array (or single-object array)
  ---------------------------------------------------------------------------
  IF jsonb_typeof(_params) = 'array'
     AND jsonb_array_length(_params) = 1
     AND jsonb_typeof(_params->0) = 'object'
  THEN
    _params := _params->0;  -- unwrap single-object array
  ELSIF jsonb_typeof(_params) = 'array' THEN
    -- Possibly positional. If so, [account] is first
    IF jsonb_array_length(_params) < 1 THEN
      RAISE EXCEPTION 'Missing "account" in positional params';
    END IF;
    _account := _params->>0;
  ELSIF jsonb_typeof(_params) = 'object' THEN
    _account := _params->>'account';
  ELSE
    RAISE EXCEPTION 'Invalid _params type: expected object or array';
  END IF;

  ---------------------------------------------------------------------------
  -- 3. Minimal validation for "account"
  ---------------------------------------------------------------------------
  IF _account IS NULL OR _account = '' THEN
    RAISE EXCEPTION 'Missing or empty "account" parameter';
  END IF;

  ---------------------------------------------------------------------------
  -- 4. Convert to account_id
  ---------------------------------------------------------------------------
  _account_id := hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_account, False),
    True
  );

  ---------------------------------------------------------------------------
  -- 5. Return same final JSON
  ---------------------------------------------------------------------------
  RETURN (
    SELECT to_jsonb(row)
    FROM (
      SELECT
        ha.name           AS account,
        ha.following      AS following_count,
        ha.followers      AS follower_count
      FROM hivemind_app.hive_accounts ha
      WHERE ha.id = _account_id
    ) row
  );
END;
$$
;
