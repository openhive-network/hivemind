DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_post_notifications;
CREATE FUNCTION hivemind_endpoints.bridge_api_post_notifications(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _post_id INT;
  _min_score SMALLINT := 25;
  _last_id INTEGER;
  _limit INTEGER := 100;
  _notifications JSONB;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author", "permlink", "min_score", "last_id", "limit"}', '{"string", "string", "number", "number", "number"}', 2);

  _post_id =
    hivemind_postgrest_utilities.find_comment_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True),
        False),
      hivemind_postgrest_utilities.valid_permlink(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True),
        False),
      True);

  _min_score = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'min_score', 2, False);
  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');

  _last_id = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'last_id', 3, False);
  _last_id = hivemind_postgrest_utilities.valid_number(_last_id, 0, NULL, NULL, 'last_id');

  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 4, False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

  RETURN (
    SELECT jsonb_agg(to_jsonb(row)) FROM
    (
      WITH notifications AS
      (
        SELECT
          hnv.id,
          hnv.type_id,
          hnv.created_at,
          hs.name as src,
          hd.name as dst,
          ha.name as author,
          hpd.permlink,
          hnv.community,
          hnv.community_title,
          hnv.payload,
          hnv.score,
          hm.mentions as number_of_mentions
        FROM
        (
          SELECT
            nv.id,
            nv.type_id,
            nv.created_at,
            nv.src,
            nv.dst,
            nv.dst_post_id,
            nv.score,
            nv.community,
            nv.community_title,
            nv.payload,
            nv.post_id
          FROM hivemind_app.hive_notification_cache nv
          WHERE
            nv.dst_post_id = _post_id
            AND nv.block_num > hivemind_app.block_before_head( '90 days' )
            AND nv.score >= _min_score
            AND NOT (_last_id <> 0 AND nv.id >= _last_id )
          ORDER BY nv.id DESC
          LIMIT _limit
        ) hnv
        JOIN hivemind_app.hive_posts hp ON hnv.post_id = hp.id
        JOIN hivemind_app.hive_accounts ha ON hp.author_id = ha.id
        JOIN hivemind_app.hive_accounts hs ON hs.id = hnv.src
        JOIN hivemind_app.hive_accounts hd ON hd.id = hnv.dst
        JOIN hivemind_app.hive_permlink_data hpd ON hp.permlink_id = hpd.id,
        lateral
        (
          SELECT
            CASE
              WHEN hnv.type_id != 16 THEN 0 --evrything else than mentions (only optimization)
              ELSE hivemind_app.get_number_of_mentions_in_post( hnv.post_id )
            END as mentions
        ) as hm
        ORDER BY hnv.id DESC
        LIMIT _limit
      )
      SELECT
        notifications.id,
        hivemind_postgrest_utilities.get_notify_type_from_id(notifications.type_id) AS type,
        notifications.score,
        hivemind_postgrest_utilities.json_date(notifications.created_at) AS date,
        hivemind_postgrest_utilities.get_notify_message(notifications) AS msg,
        (
          CASE
            WHEN notifications.permlink <> '' THEN '@' || notifications.author || '/' || notifications.permlink
            WHEN notifications.community <> '' THEN 'trending/' || notifications.community
            WHEN notifications.src <> '' THEN '@' || notifications.src
            WHEN notifications.dst <> '' THEN '@' || notifications.dst
          END
        ) AS url
      FROM notifications
      LIMIT _limit
    ) row
  );
END
$$
;