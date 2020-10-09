DROP FUNCTION IF EXISTS delete_hive_posts_mentions();

CREATE OR REPLACE FUNCTION delete_hive_posts_mentions()
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  __head_block_time TIMESTAMP;
BEGIN

  __head_block_time = head_block_time();

  DELETE FROM hive_mentions hm
  WHERE post_id in
  (
    SELECT id
    FROM hive_posts
    WHERE created_at < ( __head_block_time - '90 days'::interval )
  );

END
$function$
;
