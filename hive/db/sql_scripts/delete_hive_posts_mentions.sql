DROP FUNCTION IF EXISTS hivemind_app.delete_hive_posts_mentions();

CREATE OR REPLACE FUNCTION hivemind_app.delete_hive_posts_mentions()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  __90_days_beyond_head_block_number INTEGER;
BEGIN

  __90_days_beyond_head_block_number = hivemind_app.block_before_head('90 days'::interval);

  DELETE FROM hivemind_app.hive_mentions
  WHERE block_num < __90_days_beyond_head_block_number;

END
$function$
;
