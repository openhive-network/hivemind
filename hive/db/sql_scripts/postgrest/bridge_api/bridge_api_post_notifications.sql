DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_post_notifications;
CREATE FUNCTION hivemind_endpoints.bridge_api_post_notifications(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _author TEXT;
  _permlink TEXT;
  _min_score SMALLINT := 25;
  _last_id INTEGER;
  _limit INTEGER := 100;
  _notifications JSONB;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author", "permlink", "min_score", "last_id", "limit"}', '{"string", "string", "number", "number", "number"}');

  _author = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True);
  _author = hivemind_postgrest_utilities.valid_account(_author);

  _permlink = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True);
  _permlink = hivemind_postgrest_utilities.valid_permlink(_permlink);

  _min_score = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'min_score', 2, False);
  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');

  _last_id = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'last_id', 3, False);
  _last_id = hivemind_postgrest_utilities.valid_number(_last_id, 0, NULL, NULL, 'last_id');

  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 4, False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

  WITH raw_notifs AS (
    SELECT *
    FROM hivemind_app.post_notifications(
      (_author)::VARCHAR,
      (_permlink)::VARCHAR,
      (_min_score)::SMALLINT,
      (_last_id)::BIGINT,
      (_limit)::SMALLINT
    )
  ),
  fields AS (
    SELECT
      raw_notifs.id,
      hivemind_postgrest_utilities.get_notify_type_from_id(raw_notifs.type_id) AS type,
      raw_notifs.score,
      hivemind_postgrest_utilities.json_date(raw_notifs.created_at) AS date,
      hivemind_postgrest_utilities.get_notify_message(to_jsonb(raw_notifs)) AS msg,
      CASE
        WHEN raw_notifs.permlink <> '' THEN '@' || raw_notifs.author || '/' || raw_notifs.permlink
        WHEN raw_notifs.community <> '' THEN 'trending/' || raw_notifs.community
        WHEN raw_notifs.src <> '' THEN '@' || raw_notifs.src
        WHEN raw_notifs.dst <> '' THEN '@' || raw_notifs.dst
      END AS url
    FROM raw_notifs
  )
  SELECT jsonb_agg(fields) INTO _notifications FROM fields;

  RETURN _notifications;
END
$$
;