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

  UPDATE hivemind_app.hive_posts hp
  SET
      abs_rshares = votes_rshares.abs_rshares
     ,vote_rshares = votes_rshares.rshares
     ,sc_hot = CASE hp.is_paidout OR hp.parent_id > 0 WHEN True Then 0 ELSE hivemind_app.calculate_hot( votes_rshares.rshares, hp.created_at) END
     ,sc_trend = CASE hp.is_paidout OR hp.parent_id > 0 WHEN True Then 0 ELSE hivemind_app.calculate_trending( votes_rshares.rshares, hp.created_at) END
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
      WHERE hv.post_id = ANY(_post_ids)
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

RESET enable_seqscan;
RESET work_mem;

END;

$BODY$
;
