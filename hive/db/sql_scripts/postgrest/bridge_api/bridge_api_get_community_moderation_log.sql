DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_community_moderation_log;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_community_moderation_log(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_community_id INT;
_action_type TEXT;
_action_id SMALLINT;
_last_date TIMESTAMP;
_limit INT;
_result JSONB;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(
    _params,
    '{"community": "string", "action_type": "string", "last_date": "string", "limit": "number"}',
    1,
    NULL
  );

  _community_id =
    hivemind_postgrest_utilities.find_community_id(
      hivemind_postgrest_utilities.valid_community(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'community', True),
        False
      ),
    True);

  _action_type = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'action_type', False);
  IF _action_type IS NOT NULL AND _action_type <> '' THEN
    _action_id = hivemind_postgrest_utilities.get_moderation_action_id(_action_type);
  END IF;

  _last_date = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'last_date', False)::TIMESTAMP;

  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 1000, 'limit');

  _result = (
    SELECT jsonb_agg(row_json) FROM (
      SELECT jsonb_build_object(
        'action', hivemind_postgrest_utilities.get_moderation_action_name(ml.action),
        'actor', actor_acc.name,
        'target_account', target_acc.name,
        'target_post_author', post_author.name,
        'target_post_permlink', pd.permlink,
        'old_value', ml.old_value,
        'new_value', ml.new_value,
        'notes', ml.notes,
        'date', hivemind_postgrest_utilities.json_date(ml.created_at)
      ) AS row_json
      FROM hivemind_app.hive_moderation_log ml
      JOIN hivemind_app.hive_accounts actor_acc ON actor_acc.id = ml.actor_id
      LEFT JOIN hivemind_app.hive_accounts target_acc ON target_acc.id = ml.target_account_id
      LEFT JOIN hivemind_app.hive_posts hp ON hp.id = ml.target_post_id
      LEFT JOIN hivemind_app.hive_accounts post_author ON post_author.id = hp.author_id
      LEFT JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id
      WHERE ml.community_id = _community_id
        AND (_action_id IS NULL OR ml.action = _action_id)
        AND (_last_date IS NULL OR ml.created_at < _last_date)
      ORDER BY ml.created_at DESC, ml.id DESC
      LIMIT _limit
    ) sub
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;
