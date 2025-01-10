DROP FUNCTION IF EXISTS hivemind_app.update_notification_cache;
;
CREATE OR REPLACE FUNCTION hivemind_app.update_notification_cache(in _first_block_num INT, in _last_block_num INT, in _prune_old BOOLEAN)
RETURNS VOID
AS
$function$
DECLARE
  __limit_block hivemind_app.blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
BEGIN
  IF _first_block_num IS NULL THEN
    TRUNCATE TABLE hivemind_app.hive_notification_cache;
      ALTER SEQUENCE hivemind_app.hive_notification_cache_id_seq RESTART WITH 1;
  ELSE
    DELETE FROM hivemind_app.hive_notification_cache nc WHERE _prune_old AND nc.block_num <= __limit_block;
  END IF;

  INSERT INTO hivemind_app.hive_notification_cache
  (block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
  SELECT nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id, nv.score, nv.payload, nv.community, nv.community_title
  FROM hivemind_app.hive_raw_notifications_view nv
  WHERE nv.block_num > __limit_block AND (_first_block_num IS NULL OR nv.block_num BETWEEN _first_block_num AND _last_block_num)
  ORDER BY nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id
  ;
END
$function$
LANGUAGE plpgsql VOLATILE
;
