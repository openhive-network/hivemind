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
      hp.author_id, hp.id, hp.created_at, hp.block_num
    FROM
      hive_posts hp
    WHERE hp.depth = 0 AND hp.counter_deleted = 0 AND ((_from_block_num IS NULL AND _to_block_num IS NULL) OR (hp.block_num BETWEEN _from_block_num AND _to_block_num))
    ON CONFLICT DO NOTHING;

    INSERT INTO
      hive_feed_cache (account_id, post_id, created_at, block_num)
    SELECT
      hr.blogger_id, hr.post_id, hr.created_at, hr.block_num
    FROM
      hive_reblogs hr
    WHERE (_from_block_num IS NULL AND _to_block_num IS NULL) OR (hr.block_num BETWEEN _from_block_num AND _to_block_num)
    ON CONFLICT DO NOTHING;
END
$BODY$;

