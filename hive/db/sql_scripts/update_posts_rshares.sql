DROP FUNCTION IF EXISTS hivemind_app.update_posts_rshares;
CREATE OR REPLACE FUNCTION hivemind_app.update_posts_rshares(
    _post_ids INTEGER[]
)
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
BEGIN
SET LOCAL work_mem='4GB';
SET LOCAL enable_seqscan = off;

  INSERT INTO hivemind_app.hive_posts_rshares (post_id, abs_rshares, vote_rshares, sc_hot, sc_trend, total_votes, net_votes)
  SELECT
      votes_rshares.post_id,
      votes_rshares.abs_rshares,
      votes_rshares.rshares,
      CASE hp.is_paidout OR hp.parent_id > 0 WHEN True Then 0 ELSE hivemind_app.calculate_hot( votes_rshares.rshares, hp.created_at) END,
      CASE hp.is_paidout OR hp.parent_id > 0 WHEN True Then 0 ELSE hivemind_app.calculate_trending( votes_rshares.rshares, hp.created_at) END,
      votes_rshares.total_votes,
      votes_rshares.net_votes
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
      WHERE hv.post_id = ANY(_post_ids)
      GROUP BY hv.post_id
    ) as votes_rshares
  JOIN hivemind_app.hive_posts hp ON hp.id = votes_rshares.post_id
  WHERE hp.counter_deleted = 0
  ON CONFLICT (post_id) DO UPDATE SET
      abs_rshares = EXCLUDED.abs_rshares,
      vote_rshares = EXCLUDED.vote_rshares,
      sc_hot = EXCLUDED.sc_hot,
      sc_trend = EXCLUDED.sc_trend,
      total_votes = EXCLUDED.total_votes,
      net_votes = EXCLUDED.net_votes
  WHERE
      hive_posts_rshares.abs_rshares != EXCLUDED.abs_rshares
      OR hive_posts_rshares.vote_rshares != EXCLUDED.vote_rshares
      OR hive_posts_rshares.total_votes != EXCLUDED.total_votes
      OR hive_posts_rshares.net_votes != EXCLUDED.net_votes;

RESET enable_seqscan;
RESET work_mem;

END;

$BODY$
;
