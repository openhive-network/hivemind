DROP FUNCTION IF EXISTS hivemind_app.prune_notification_cache;
CREATE OR REPLACE FUNCTION hivemind_app.prune_notification_cache(in _block_num INT)
RETURNS VOID
AS
$function$
DECLARE
  __limit_block hivemind_app.blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
BEGIN
  IF _block_num % 1200 = 0 THEN -- once per hour
    DELETE FROM hivemind_app.hive_notification_cache nc WHERE nc.block_num <= __limit_block;
  END IF;
END
$function$
LANGUAGE plpgsql VOLATILE
;
