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
  , sc_hot = CASE hp.is_paidout WHEN True Then 0 ELSE calculate_hot( votes_rshares.rshares, hp.created_at) END
  , sc_trend = CASE hp.is_paidout WHEN True Then 0 ELSE calculate_tranding( votes_rshares.rshares, hp.created_at) END
FROM
  (
    SELECT
        hv.post_id
      , SUM( hv.rshares ) as rshares
      , SUM( ABS( hv.rshares ) ) as abs_rshares
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
AND (hp.abs_rshares != votes_rshares.abs_rshares OR hp.vote_rshares != votes_rshares.rshares);
RESET work_mem;
RESET enable_seqscan;
END;
$BODY$
;
