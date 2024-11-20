DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_account_notifications;
CREATE FUNCTION hivemind_endpoints.bridge_api_account_notifications(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account_id INT;
  _min_score SMALLINT;
  _last_id INTEGER;
  _limit INTEGER;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account", "min_score", "last_id", "limit"}', '{"string", "number", "number", "number"}', 1);

  _account_id = 
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 1, True),
      False),
    True);

  _min_score = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'min_score', 1, False);
  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');

  _last_id = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'last_id', 2, False);
  _last_id = hivemind_postgrest_utilities.valid_number(_last_id, 0, NULL, NULL, 'last_id');

  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 3, False);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

  RETURN(
    SELECT jsonb_agg(
      jsonb_build_object(
        'id', hive_notification_cache.id,
        'type', hivemind_postgrest_utilities.get_notify_type_from_id(hive_notification_cache.type_id),
        'score', hive_notification_cache.score,
        'date', hivemind_postgrest_utilities.json_date(hive_notification_cache.created_at),
        'msg', hivemind_postgrest_utilities.get_notify_message(hive_notification_cache),
        'url',  CASE
                  WHEN hive_notification_cache.permlink <> '' THEN '@' || hive_notification_cache.author || '/' || hive_notification_cache.permlink
                  WHEN hive_notification_cache.community <> '' THEN 'trending/' || hive_notification_cache.community
                  WHEN hive_notification_cache.src <> '' THEN '@' || hive_notification_cache.src
                  WHEN hive_notification_cache.dst <> '' THEN '@' || hive_notification_cache.dst
                END
      )
    ) FROM (
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
        hnv.score,
        hnv.payload,
        hm.mentions as number_of_mentions
        FROM
        (
          SELECT
            nv.id,
            nv.type_id,
            nv.created_at,
            nv.score,
            nv.community,
            nv.community_title,
            nv.post_id,
            nv.src,
            nv.dst,
            nv.payload
          FROM hivemind_app.hive_notification_cache nv
          WHERE
            nv.dst = _account_id
            AND nv.block_num > hivemind_app.block_before_head( '90 days' )
            AND nv.score >= _min_score
            AND NOT( _last_id <> 0 AND nv.id >= _last_id )
          ORDER BY nv.id DESC
          LIMIT _limit
        ) hnv
        JOIN hivemind_app.hive_posts hp on hnv.post_id = hp.id
        JOIN hivemind_app.hive_accounts ha on hp.author_id = ha.id
        JOIN hivemind_app.hive_accounts hs on hs.id = hnv.src
        JOIN hivemind_app.hive_accounts hd on hd.id = hnv.dst
        JOIN hivemind_app.hive_permlink_data hpd on hp.permlink_id = hpd.id,
        lateral
        (
          SELECT
            CASE
                WHEN hnv.type_id != 16 THEN 0 --evrything else than mentions (only optimization)
                ELSE hivemind_app.get_number_of_mentions_in_post( hnv.post_id )
            END as mentions
        ) as hm
      ) hive_notification_cache
  );
END
$$
;