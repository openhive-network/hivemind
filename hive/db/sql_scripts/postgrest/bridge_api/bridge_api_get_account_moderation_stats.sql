DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_account_moderation_stats;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_account_moderation_stats(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_account TEXT;
_account_id INT;
_community TEXT;
_community_id INT;
_last_date TIMESTAMP;
_limit INT;
_stats JSONB;
_actions JSONB;
_result JSONB;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(
    _params,
    '{"account": "string", "community": "string", "last_date": "string", "limit": "number"}',
    1,
    NULL
  );

  _account = hivemind_postgrest_utilities.valid_account(
    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
    False
  );
  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  _community = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'community', False);
  IF _community IS NOT NULL AND _community <> '' THEN
    _community_id = hivemind_postgrest_utilities.find_community_id(
      hivemind_postgrest_utilities.valid_community(_community, False),
      True
    );
  END IF;

  _last_date = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'last_date', False)::TIMESTAMP;

  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 1000, 'limit');

  SELECT jsonb_build_object(
    'times_muted', COALESCE(SUM(CASE WHEN action = 3 THEN 1 ELSE 0 END), 0),
    'times_unmuted', COALESCE(SUM(CASE WHEN action = 4 THEN 1 ELSE 0 END), 0),
    'times_flagged', COALESCE(SUM(CASE WHEN action = 7 THEN 1 ELSE 0 END), 0),
    'posts_pinned', COALESCE(SUM(CASE WHEN action = 5 THEN 1 ELSE 0 END), 0),
    'posts_unpinned', COALESCE(SUM(CASE WHEN action = 6 THEN 1 ELSE 0 END), 0),
    'role_changes', COALESCE(SUM(CASE WHEN action = 1 THEN 1 ELSE 0 END), 0),
    'title_changes', COALESCE(SUM(CASE WHEN action = 2 THEN 1 ELSE 0 END), 0)
  ) INTO _stats
  FROM hivemind_app.hive_moderation_log
  WHERE target_account_id = _account_id
    AND (_community_id IS NULL OR community_id = _community_id);

  SELECT COALESCE(jsonb_agg(row_json), '[]'::jsonb) INTO _actions FROM (
    SELECT jsonb_build_object(
      'action', hivemind_postgrest_utilities.get_moderation_action_name(ml.action),
      'community', hc.name,
      'community_title', hc.title,
      'actor', actor_acc.name,
      'date', hivemind_postgrest_utilities.json_date(ml.created_at),
      'notes', ml.notes
    ) AS row_json
    FROM hivemind_app.hive_moderation_log ml
    JOIN hivemind_app.hive_accounts actor_acc ON actor_acc.id = ml.actor_id
    JOIN hivemind_app.hive_communities hc ON hc.id = ml.community_id
    WHERE ml.target_account_id = _account_id
      AND (_community_id IS NULL OR ml.community_id = _community_id)
      AND (_last_date IS NULL OR ml.created_at < _last_date)
    ORDER BY ml.created_at DESC
    LIMIT _limit
  ) sub;

  _result = jsonb_build_object(
    'account', _account,
    'stats', _stats,
    'actions', _actions
  );

  RETURN _result;
END
$$
;
