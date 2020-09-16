DROP FUNCTION IF EXISTS update_feed_cache(in _from_block_num INTEGER, in _to_block_num INTEGER);
CREATE OR REPLACE FUNCTION update_feed_cache(in _from_block_num INTEGER, in _to_block_num INTEGER)
RETURNS void
LANGUAGE 'plpgsql'
VOLATILE
AS $BODY$
BEGIN
    INSERT INTO
      hive_feed_cache (account_id, post_id, created_at, block_num)
    SELECT
      hive_posts.author_id, hive_posts.id, hive_posts.created_at, hive_posts.block_num
    FROM
      hive_posts
    WHERE depth = 0 AND counter_deleted = 0 AND ((_from_block_num IS NULL AND _to_block_num IS NULL) OR (block_num BETWEEN _from_block_num AND _to_block_num))
    ON CONFLICT DO NOTHING;

    INSERT INTO
      hive_feed_cache (account_id, post_id, created_at, block_num)
    SELECT
      hive_reblogs.blogger_id, hive_reblogs.post_id, hive_reblogs.created_at, hive_reblogs.block_num
    FROM
      hive_reblogs
    WHERE (_from_block_num IS NULL AND _to_block_num IS NULL) OR (block_num BETWEEN _from_block_num AND _to_block_num)
    ON CONFLICT DO NOTHING;
END
$BODY$;

