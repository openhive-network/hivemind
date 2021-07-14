DROP FUNCTION IF EXISTS update_posts_rshares;
CREATE OR REPLACE FUNCTION update_posts_rshares(
    _first_block hive_blocks.num%TYPE
  , _last_block hive_blocks.num%TYPE
)
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
BEGIN
SET LOCAL work_mem='2GB';
SET LOCAL enable_seqscan=False;
UPDATE hive_posts hp
SET
    abs_rshares = votes_rshares.abs_rshares
  , vote_rshares = votes_rshares.rshares
  , sc_hot = calculate_hot( votes_rshares.rshares, hp.created_at)
  , sc_trend = calculate_trending( votes_rshares.rshares, hp.created_at)
  , total_votes = votes_rshares.total_votes
  , net_votes = votes_rshares.net_votes
FROM
  (
    SELECT
        hv.post_id
      , SUM( hv.rshares ) as rshares
      , SUM( ABS( hv.rshares ) ) as abs_rshares
      , SUM( 1 ) as total_votes
      , SUM( CASE
              WHEN hv.vote_percent > 0 THEN 1
              WHEN hv.vote_percent = 0 THEN 0
              ELSE -1
            END ) as net_votes
    FROM hive_votes hv
    WHERE EXISTS
      (
        SELECT NULL
        FROM hive_votes hv2
        WHERE hv2.post_id = hv.post_id AND hv2.block_num BETWEEN _first_block AND _last_block
      )
    GROUP BY hv.post_id
  ) as votes_rshares
WHERE hp.id = votes_rshares.post_id
AND NOT hp.is_paidout AND hp.counter_deleted = 0;
RESET work_mem;
RESET enable_seqscan;
END;
$BODY$
;
