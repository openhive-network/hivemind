DROP FUNCTION IF EXISTS delete_hive_posts_mentions();

CREATE OR REPLACE FUNCTION delete_hive_posts_mentions()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  LAST_BLOCK_TIME TIMESTAMP;
BEGIN

  LAST_BLOCK_TIME = ( SELECT created_at FROM hive_blocks ORDER BY num DESC LIMIT 1 );

  DELETE FROM hive_mentions hm
  WHERE post_id in
  (
    SELECT id
    FROM hive_posts
    WHERE created_at < ( LAST_BLOCK_TIME - '90 days'::interval )
  );

END
$function$
;
