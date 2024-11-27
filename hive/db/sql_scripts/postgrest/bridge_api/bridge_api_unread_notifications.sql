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
BEGIN
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"account": "string", "min_score": "number"}', 1, '{"account": "invalid account name type"}');

  _account_id = 
    hivemind_postgrest_utilities.find_account_id(
      hivemind_postgrest_utilities.valid_account(
        hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
      False),
    True);

  _min_score = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'min_score', False);
  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');

  SELECT ha.lastread_at INTO _last_read_at FROM hivemind_app.hive_accounts ha WHERE ha.id = _account_id;

  SELECT
    COALESCE( -- bridge_api_unread_notifications
      (
        SELECT hb.num
        FROM hive.blocks_view hb -- very important for performance (originally it was a hivemind_app_blocks_view)
        WHERE hb.created_at <= _last_read_at
      ORDER by hb.created_at desc
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
        WHERE hnv.dst = _account_id  AND hnv.block_num > _limit_block AND hnv.block_num > _last_read_at_block AND hnv.score >= _min_score
      )
    );
END
$$
;