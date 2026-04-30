DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_unread_notifications;
CREATE FUNCTION hivemind_endpoints.bridge_api_unread_notifications(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account_id INT;
  _min_score SMALLINT := 25;
  _last_read_at TIMESTAMP WITHOUT TIME ZONE;
  _last_read_at_block hivemind_app.blocks_view.num%TYPE;
  _limit_block hivemind_app.blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
  _types TEXT[];
  _type_ids INT[];
  _community TEXT;
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string", "min_score": "number", "type": "array", "community": "string"}', 1, '{"account": "invalid account name type"}');

  _account_id =
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
      False),
    True);

  _min_score = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'min_score', False);
  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');

  _types = hivemind_postgrest_utilities.parse_string_array_argument_from_json(_params, 'type', False, 17);
  IF _types IS NOT NULL AND array_length(_types, 1) IS NOT NULL THEN
    SELECT array_agg(hivemind_postgrest_utilities.get_notify_id_from_type(t))
    INTO _type_ids
    FROM unnest(_types) AS t;
  END IF;

  _community = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'community', False);
  IF _community = '' THEN
    _community = NULL;
  END IF;
  IF _community IS NOT NULL THEN
    _community = hivemind_postgrest_utilities.valid_community(_community, False);
  END IF;

  SELECT ha.lastread_at INTO _last_read_at FROM hivemind_app.hive_accounts ha WHERE ha.id = _account_id;

  SELECT
    COALESCE( -- bridge_api_unread_notifications
      (
        SELECT hb.num
        FROM hive.blocks_view hb -- very important for performance (originally it was a hivemind_app_blocks_view)
        WHERE hb.created_at <= _last_read_at
      ORDER by hb.created_at desc, hb.num DESC
      LIMIT 1
      ),
    _limit_block)
  INTO _last_read_at_block;

  RETURN
    jsonb_build_object(
      'lastread', to_char(_last_read_at, 'YYYY-MM-DD HH24:MI:SS'),
      'unread', (
        SELECT count(1)
        FROM hivemind_app.hive_notification_cache hnv
        WHERE hnv.dst = _account_id
          AND hnv.block_num > _limit_block
          AND hnv.block_num > _last_read_at_block
          AND hnv.score >= _min_score
          AND (_type_ids IS NULL OR hnv.type_id = ANY(_type_ids))
          AND (_community IS NULL OR hnv.type_id = 15 OR hnv.community = _community)
      )
    );
END
$$
;