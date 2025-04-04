DROP FUNCTION IF EXISTS hivemind_app.update_notification_cache;
CREATE OR REPLACE FUNCTION hivemind_app.update_notification_cache(in _first_block_num INT, in _last_block_num INT, in _prune_old BOOLEAN)
RETURNS VOID
AS
$function$
DECLARE
  __limit_block hivemind_app.blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
BEGIN
  IF _first_block_num IS NOT NULL THEN
    DELETE FROM hivemind_app.hive_notification_cache nc WHERE _prune_old AND nc.block_num <= __limit_block;
  END IF;
END
$function$
LANGUAGE plpgsql VOLATILE
;
