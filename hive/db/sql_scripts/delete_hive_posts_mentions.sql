DROP FUNCTION IF EXISTS delete_hive_posts_mentions();

CREATE OR REPLACE FUNCTION delete_hive_posts_mentions()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  __90_days_beyond_head_block_number INTEGER;
BEGIN

  __90_days_beyond_head_block_number = block_before_head('90 days'::interval);

  DELETE FROM hive_mentions
  WHERE block_num < __90_days_beyond_head_block_number;

END
$function$
;
