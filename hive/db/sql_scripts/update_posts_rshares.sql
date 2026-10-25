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

DROP FUNCTION IF EXISTS hivemind_app.recalculate_all_posts_rshares;
DROP FUNCTION IF EXISTS hivemind_app.recalculate_all_posts_votes_and_children;
--- Full recomputation of the vote aggregates (update_posts_rshares' columns) and
--- `children` of every post. Both are written by one UPDATE, so a hive_posts row
--- gets one new version instead of one per aggregate: this runs with every
--- hive_posts index in place, and a version that changes sc_hot or sc_trend
--- (both indexed) is inserted into each of them.
CREATE OR REPLACE FUNCTION hivemind_app.recalculate_all_posts_votes_and_children()
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
DECLARE
  __depth INT;
BEGIN
SET LOCAL work_mem='4GB';

  SELECT MAX(hp.depth) INTO __depth FROM hivemind_app.hive_posts hp;

  CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app.__post_children
  (
    id INT NOT NULL,
    child_count INT NOT NULL,
    CONSTRAINT __post_children_pkey PRIMARY KEY (id)
  );

  TRUNCATE TABLE hivemind_app.__post_children;

  -- Deepest level first: a post's count is complete before its parent's is summed.
  WHILE __depth >= 0 LOOP
    INSERT INTO hivemind_app.__post_children
    (id, child_count)
      SELECT
        h1.parent_id AS queried_parent,
        SUM(COALESCE(pc.child_count, 0) + 1) AS count
      FROM hivemind_app.hive_posts h1
      LEFT JOIN hivemind_app.__post_children pc ON pc.id = h1.id
      WHERE (h1.parent_id != 0 OR __depth = 0) AND h1.counter_deleted = 0 AND h1.id != 0 AND h1.depth = __depth
      GROUP BY h1.parent_id

    ON CONFLICT ON CONSTRAINT __post_children_pkey DO UPDATE
      SET child_count = hivemind_app.__post_children.child_count + excluded.child_count
    ;

    __depth := __depth -1;
  END LOOP;

  -- Vote aggregates go to posts with votes that are not deleted, `children` to
  -- posts with a count that differs; each keeps its old value elsewhere.
  UPDATE hivemind_app.hive_posts hp
  SET
      abs_rshares = CASE WHEN s.voted AND hp.counter_deleted = 0 THEN s.abs_rshares ELSE hp.abs_rshares END
     ,vote_rshares = CASE WHEN s.voted AND hp.counter_deleted = 0 THEN s.rshares ELSE hp.vote_rshares END
     ,sc_hot = CASE
                 WHEN NOT (s.voted AND hp.counter_deleted = 0) THEN hp.sc_hot
                 WHEN hp.is_paidout OR hp.parent_id > 0 THEN 0
                 ELSE hivemind_app.calculate_hot( s.rshares, hp.created_at)
               END
     ,sc_trend = CASE
                   WHEN NOT (s.voted AND hp.counter_deleted = 0) THEN hp.sc_trend
                   WHEN hp.is_paidout OR hp.parent_id > 0 THEN 0
                   ELSE hivemind_app.calculate_trending( s.rshares, hp.created_at)
                 END
     ,total_votes = CASE WHEN s.voted AND hp.counter_deleted = 0 THEN s.total_votes ELSE hp.total_votes END
     ,net_votes = CASE WHEN s.voted AND hp.counter_deleted = 0 THEN s.net_votes ELSE hp.net_votes END
     ,children = COALESCE(s.child_count, hp.children)
  FROM
    (
      SELECT
          COALESCE(votes_rshares.post_id, pc.id) AS post_id
        , votes_rshares.post_id IS NOT NULL AS voted
        , votes_rshares.rshares
        , votes_rshares.abs_rshares
        , votes_rshares.total_votes
        , votes_rshares.net_votes
        , pc.child_count
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
          GROUP BY hv.post_id
        ) as votes_rshares
      FULL JOIN hivemind_app.__post_children pc ON pc.id = votes_rshares.post_id
    ) as s
  WHERE hp.id = s.post_id
  AND ((s.voted AND hp.counter_deleted = 0) OR s.child_count != hp.children);

  TRUNCATE TABLE hivemind_app.__post_children;

RESET work_mem;

END;

$BODY$
;
