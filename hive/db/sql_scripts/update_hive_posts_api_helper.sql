DROP FUNCTION IF EXISTS public.update_hive_posts_api_helper(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.update_hive_posts_api_helper(in _first_block_num INTEGER, _last_block_num INTEGER)
  RETURNS void
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
BEGIN
IF _first_block_num IS NULL OR _last_block_num IS NULL THEN
  -- initial creation of table.
  INSERT INTO hive_posts_api_helper
  (id, author_s_permlink)
  SELECT hp.id, hp.author || '/' || hp.permlink
  FROM hive_posts_view hp
  ;
ELSE
  -- Regular incremental update.
  INSERT INTO hive_posts_api_helper
  (id, author_s_permlink)
  SELECT hp.id, hp.author || '/' || hp.permlink
  FROM hive_posts_view hp
  WHERE hp.block_num BETWEEN _first_block_num AND _last_block_num AND
          NOT EXISTS (SELECT NULL FROM hive_posts_api_helper h WHERE h.id = hp.id)
  ;
END IF;

END
$BODY$
;
