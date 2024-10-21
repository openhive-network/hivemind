DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_account_notifications;
CREATE FUNCTION hivemind_endpoints.bridge_api_account_notifications(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _min_score SMALLINT := 25;
  _last_id INTEGER;
  _limit INTEGER := 100;
  _notifications JSONB;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account", "min_score", "last_id", "limit"}', '{"string", "number", "number", "number"}');

  _account = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 0, True);
  _account = hivemind_postgrest_utilities.valid_account(_account);

  _min_score = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'min_score', 1, False);
  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');

  _last_id = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'last_id', 2, False);
  _last_id = hivemind_postgrest_utilities.valid_number(_last_id, 0, NULL, NULL, 'last_id');

  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 3, False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');


  SELECT jsonb_agg(
    jsonb_build_object(
      'id', hive_notification_cache.id,
      'type', hivemind_postgrest_utilities.get_notify_type_from_id(hive_notification_cache.type_id),
      'score', hive_notification_cache.score,
      'date', hivemind_postgrest_utilities.json_date(hive_notification_cache.created_at),
      'msg', hivemind_postgrest_utilities.get_notify_message(to_jsonb(hive_notification_cache)),
      'url', CASE
          WHEN hive_notification_cache.permlink <> '' THEN '@' || hive_notification_cache.author || '/' || hive_notification_cache.permlink
          WHEN hive_notification_cache.community <> '' THEN 'trending/' || hive_notification_cache.community
          WHEN hive_notification_cache.src <> '' THEN '@' || hive_notification_cache.src
          WHEN hive_notification_cache.dst <> '' THEN '@' || hive_notification_cache.dst
       END
    )
  )
  INTO _notifications
  FROM (
    SELECT *
    FROM hivemind_app.account_notifications(
      (_account)::VARCHAR,
      (_min_score)::SMALLINT,
      (_last_id)::BIGINT,
      (_limit)::SMALLINT
    )
  ) hive_notification_cache;

  RETURN _notifications;
END
$$
;