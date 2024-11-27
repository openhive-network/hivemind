DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_profile;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_profile(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _observer_id INT;
  _result JSONB;
  _followed_muted JSONB;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string", "observer": "string"}', 1, '{"account": "invalid account name type"}');
  _account = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True);
  _account = hivemind_postgrest_utilities.valid_account(_account, False);

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(
      hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False),
      True),
    True);

  SELECT jsonb_build_object(
    'id', row.id,
    'name', row.name,
    'created', hivemind_postgrest_utilities.json_date(row.created_at),
    'active', hivemind_postgrest_utilities.json_date(row.active_at),
    'post_count', row.post_count,
    'reputation', hivemind_postgrest_utilities.rep_log10(row.reputation),
    'blacklists', to_jsonb('{}'::INT[]),
    'stats', jsonb_build_object('rank', row.rank, 'following', row.following, 'followers', row.followers),
    'json_metadata', row.json_metadata,
    'posting_json_metadata', row.posting_json_metadata
    ) FROM (
      SELECT * FROM hivemind_app.hive_accounts_info_view WHERE name = _account
    ) row INTO _result;
  
  IF _result IS NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Account ''' || _account || ''' does not exist');
  END IF;

  IF _observer_id IS NOT NULL AND _observer_id <> 0 THEN
    SELECT jsonb_build_object(
      'followed', (CASE WHEN state = 1 THEN True ELSE False END),
      'muted', (CASE WHEN state = 2 THEN True ELSE False END)
    ) FROM (
      SELECT state FROM hivemind_app.hive_follows WHERE follower = _observer_id AND following = (_result->'id')::INT
    ) row INTO _followed_muted;
    IF _followed_muted IS NOT NULL THEN
      IF NOT (_followed_muted->'muted')::BOOLEAN THEN
        _followed_muted = _followed_muted - 'muted';
      END IF;
      _result = jsonb_set(_result, '{context}', _followed_muted);
      _followed_muted = NULL;
    ELSE
      _result = jsonb_set(_result, '{context}', '{}'::jsonb);
      _result = jsonb_set(_result, '{context,followed}', to_jsonb(False));
    END IF;
  END IF;

  _result = jsonb_set(_result, '{metadata}', hivemind_postgrest_utilities.extract_profile_metadata(_result->>'json_metadata', _result->>'posting_json_metadata'));
  _result = _result - 'json_metadata';
  _result = _result - 'posting_json_metadata';

  RETURN _result;
END
$$
;