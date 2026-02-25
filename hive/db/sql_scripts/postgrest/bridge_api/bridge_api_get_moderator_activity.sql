DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_moderator_activity;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_moderator_activity(IN _params JSONB)
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

  _result = (
    SELECT jsonb_agg(row_json) FROM (
      SELECT jsonb_build_object(
        'action', hivemind_postgrest_utilities.get_moderation_action_name(ml.action),
        'community', hc.name,
        'community_title', hc.title,
        'target_account', target_acc.name,
        'target_post_author', post_author.name,
        'target_post_permlink', pd.permlink,
        'old_value', ml.old_value,
        'new_value', ml.new_value,
        'notes', ml.notes,
        'date', hivemind_postgrest_utilities.json_date(ml.created_at)
      ) AS row_json
      FROM hivemind_app.hive_moderation_log ml
      JOIN hivemind_app.hive_communities hc ON hc.id = ml.community_id
      LEFT JOIN hivemind_app.hive_accounts target_acc ON target_acc.id = ml.target_account_id
      LEFT JOIN hivemind_app.hive_posts hp ON hp.id = ml.target_post_id
      LEFT JOIN hivemind_app.hive_accounts post_author ON post_author.id = hp.author_id
      LEFT JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id
      WHERE ml.actor_id = _account_id
        AND (_community_id IS NULL OR ml.community_id = _community_id)
        AND (_last_date IS NULL OR ml.created_at < _last_date)
      ORDER BY ml.created_at DESC, ml.id DESC
      LIMIT _limit
    ) sub
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;
