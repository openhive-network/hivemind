DROP FUNCTION IF EXISTS hivemind_app.update_hive_posts_api_helper(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION hivemind_app.update_hive_posts_api_helper(in _first_block_num INTEGER, _last_block_num INTEGER)
  RETURNS void
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
BEGIN
IF _first_block_num IS NULL OR _last_block_num IS NULL THEN
  -- initial creation of table.
  INSERT INTO hivemind_app.hive_posts_api_helper
  (id, author_s_permlink)
  SELECT hp.id, hp.author || '/' || hp.permlink
  FROM hivemind_app.live_posts_comments_view hp
  JOIN hivemind_app.hive_accounts ha ON (ha.id = hp.author_id)
  JOIN hivemind_app.hive_permlink_data hpd_p ON (hpd_p.id = hp.permlink_id)
  ;
ELSE
  -- Regular incremental update.
  INSERT INTO hivemind_app.hive_posts_api_helper (id, author_s_permlink)
  SELECT hp.id, ha.name || '/' || hpd_p.permlink
  FROM hivemind_app.live_posts_comments_view hp
  JOIN hivemind_app.hive_accounts ha ON (ha.id = hp.author_id)
  JOIN hivemind_app.hive_permlink_data hpd_p ON (hpd_p.id = hp.permlink_id)
  WHERE hp.block_num BETWEEN _first_block_num AND _last_block_num
  ON CONFLICT (id) DO NOTHING
  ;
END IF;

END
$BODY$
;
