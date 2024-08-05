DROP FUNCTION IF EXISTS hivemind_app.update_posts_rshares;
CREATE OR REPLACE FUNCTION hivemind_app.update_posts_rshares(
    _first_block hivemind_app.blocks_view.num%TYPE
  , _last_block hivemind_app.blocks_view.num%TYPE
)
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
BEGIN
SET LOCAL work_mem='2GB';

IF (_last_block - _first_block) > 10000 THEN
  WITH votes_rshares_view AS MATERIALIZED
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
    FROM hivemind_app.hive_votes hv
    GROUP BY hv.post_id
  )
  UPDATE hivemind_app.hive_posts hp
  SET
       abs_rshares = votes_rshares.abs_rshares
      ,vote_rshares = votes_rshares.rshares
      ,sc_hot = CASE hp.is_paidout WHEN True Then 0 ELSE hivemind_app.calculate_hot( votes_rshares.rshares, hp.created_at) END
      ,sc_trend = CASE hp.is_paidout WHEN True Then 0 ELSE hivemind_app.calculate_trending( votes_rshares.rshares, hp.created_at) END
      ,total_votes = votes_rshares.total_votes
      ,net_votes = votes_rshares.net_votes
  FROM votes_rshares_view votes_rshares
  WHERE hp.id = votes_rshares.post_id
  AND hp.counter_deleted = 0;
ELSE
  UPDATE hivemind_app.hive_posts hp
  SET
      abs_rshares = votes_rshares.abs_rshares
     ,vote_rshares = votes_rshares.rshares
     ,sc_hot = CASE hp.is_paidout WHEN True Then 0 ELSE hivemind_app.calculate_hot( votes_rshares.rshares, hp.created_at) END
     ,sc_trend = CASE hp.is_paidout WHEN True Then 0 ELSE hivemind_app.calculate_trending( votes_rshares.rshares, hp.created_at) END
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
      FROM hivemind_app.hive_votes hv
      WHERE EXISTS
        (
          SELECT NULL
          FROM hivemind_app.hive_votes hv2
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

END;

$BODY$
;
