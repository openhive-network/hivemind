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
DECLARE
  __version INT;
BEGIN
SET LOCAL work_mem='2GB';

SELECT current_setting('server_version_num')::INT INTO __version;

IF __version >= 120000 THEN
  SET LOCAL jit_above_cost = -1;
  SET LOCAL jit_inline_above_cost = -1;
  SET LOCAL jit_optimize_above_cost = -1;
END IF;

IF (_last_block - _first_block) > 10000 THEN
  UPDATE hive_posts hp
  SET
       abs_rshares = votes_rshares.abs_rshares
      ,vote_rshares = votes_rshares.rshares
      ,sc_hot = CASE hp.is_paidout WHEN True Then 0 ELSE calculate_hot( votes_rshares.rshares, hp.created_at) END
      ,sc_trend = CASE hp.is_paidout WHEN True Then 0 ELSE calculate_trending( votes_rshares.rshares, hp.created_at) END
      ,total_votes = votes_rshares.total_votes
      ,net_votes = votes_rshares.net_votes
  FROM
    (
      SELECT
          hv.post_id
        , SUM( hv.rshares ) as rshares
        , SUM( ABS( hv.rshares ) ) as abs_rshares
        , SUM( CASE hv.is_effective WHEN True THEN 1 ELSE 0 END ) as total_votes
        , SUM( CASE
                WHEN hv.rshares > 0 THEN 1
                WHEN hv.rshares = 0 THEN 0
                ELSE -1
              END ) as net_votes
      FROM hive_votes hv
      GROUP BY hv.post_id
    ) as votes_rshares
  WHERE hp.id = votes_rshares.post_id
  AND hp.counter_deleted = 0
  AND (
    hp.abs_rshares != votes_rshares.abs_rshares
    OR hp.vote_rshares != votes_rshares.rshares
    OR hp.total_votes != votes_rshares.total_votes
    OR hp.net_votes != votes_rshares.net_votes
  );
ELSE
  UPDATE hive_posts hp
  SET
      abs_rshares = votes_rshares.abs_rshares
     ,vote_rshares = votes_rshares.rshares
     ,sc_hot = CASE hp.is_paidout WHEN True Then 0 ELSE calculate_hot( votes_rshares.rshares, hp.created_at) END
     ,sc_trend = CASE hp.is_paidout WHEN True Then 0 ELSE calculate_trending( votes_rshares.rshares, hp.created_at) END
     ,total_votes = votes_rshares.total_votes
     ,net_votes = votes_rshares.net_votes
  FROM
    (
      SELECT
          hv.post_id
        , SUM( hv.rshares ) as rshares
        , SUM( ABS( hv.rshares ) ) as abs_rshares
        , SUM( CASE hv.is_effective WHEN True THEN 1 ELSE 0 END ) as total_votes
        , SUM( CASE
                WHEN hv.rshares > 0 THEN 1
                WHEN hv.rshares = 0 THEN 0
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
  AND hp.counter_deleted = 0
  AND (
    hp.abs_rshares != votes_rshares.abs_rshares
    OR hp.vote_rshares != votes_rshares.rshares
    OR hp.total_votes != votes_rshares.total_votes
    OR hp.net_votes != votes_rshares.net_votes
  );
END IF;

RESET work_mem;
IF __version >= 120000 THEN
  RESET jit_above_cost;
  RESET jit_inline_above_cost;
  RESET jit_optimize_above_cost;
END IF;

END;

$BODY$
;
