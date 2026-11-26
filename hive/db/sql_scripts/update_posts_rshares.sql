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
-- One batch's voted posts: its hash aggregate holds about 430 bytes per post.
SET LOCAL work_mem='512MB';
SET LOCAL enable_seqscan = off;

  -- The changed rows are locked in id order before any is updated (changed is the
  -- UPDATE's only source of rows, so each row is locked there first), as the posts phase
  -- locks its rows (process_posts_from_staging, Step 0), which pipelined massive sync runs
  -- beside this.
  WITH votes_rshares AS MATERIALIZED
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
    ),
  changed AS MATERIALIZED
    (
      SELECT vr.*
      FROM votes_rshares vr
      JOIN hivemind_app.hive_posts hp ON hp.id = vr.post_id
      WHERE hp.counter_deleted = 0
      AND (
        hp.abs_rshares != vr.abs_rshares
        OR hp.vote_rshares != vr.rshares
        OR hp.total_votes != vr.total_votes
        OR hp.net_votes != vr.net_votes
      )
      ORDER BY hp.id
      FOR NO KEY UPDATE OF hp
    )
  UPDATE hivemind_app.hive_posts hp
  SET
      abs_rshares = votes_rshares.abs_rshares
     ,vote_rshares = votes_rshares.rshares
     ,sc_hot = CASE hp.is_paidout OR hp.parent_id > 0 WHEN True Then 0 ELSE hivemind_app.calculate_hot( votes_rshares.rshares, hp.created_at) END
     ,sc_trend = CASE hp.is_paidout OR hp.parent_id > 0 WHEN True Then 0 ELSE hivemind_app.calculate_trending( votes_rshares.rshares, hp.created_at) END
     ,total_votes = votes_rshares.total_votes
     ,net_votes = votes_rshares.net_votes
  FROM changed votes_rshares
  WHERE hp.id = votes_rshares.post_id;

RESET enable_seqscan;
RESET work_mem;

END;

$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.recalculate_all_posts_rshares;
DROP FUNCTION IF EXISTS hivemind_app.recalculate_all_posts_votes_and_children;
DROP FUNCTION IF EXISTS hivemind_app.prepare_posts_children;
DROP FUNCTION IF EXISTS hivemind_app.recalculate_posts_votes_and_children;
--- Full recomputation of the vote aggregates (update_posts_rshares' columns) and
--- `children` of every post, in three steps that finalization runs on several
--- connections: prepare_posts_children once, recalculate_posts_votes_and_children
--- over disjoint post id ranges covering 0 .. 2147483647, any number at a time,
--- then a TRUNCATE of __post_children. recalculate_all_posts_votes_and_children
--- runs the three on one connection.
---
--- The child count of every post into __post_children, which the ranges read. The
--- table is UNLOGGED and holds no state of its own: a step interrupted anywhere is
--- redone from the start of prepare_posts_children.
CREATE OR REPLACE FUNCTION hivemind_app.prepare_posts_children()
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
DECLARE
  __depth INT;
BEGIN
-- Each hash node may hold work_mem * hash_mem_multiplier, and the host this runs on
-- is shared: a bound of 512MB lets the child-count loop's hash nodes spill to disk
-- instead of growing to many GB.
SET LOCAL work_mem='512MB';

  -- The posts the child count reads, in one scan of hive_posts, grouped by depth so
  -- that each level of the loop below reads only its own pages.
  DROP TABLE IF EXISTS hivemind_app.__post_tree;
  CREATE UNLOGGED TABLE hivemind_app.__post_tree AS
    SELECT hp.id, hp.parent_id, hp.depth
    FROM hivemind_app.hive_posts hp
    WHERE hp.counter_deleted = 0 AND hp.id != 0
    ORDER BY hp.depth;
  CREATE INDEX __post_tree_depth_idx ON hivemind_app.__post_tree (depth);
  ANALYZE hivemind_app.__post_tree;

  SELECT MAX(pt.depth) INTO __depth FROM hivemind_app.__post_tree pt;

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
      FROM hivemind_app.__post_tree h1
      LEFT JOIN hivemind_app.__post_children pc ON pc.id = h1.id
      WHERE (h1.parent_id != 0 OR __depth = 0) AND h1.depth = __depth
      GROUP BY h1.parent_id

    ON CONFLICT ON CONSTRAINT __post_children_pkey DO UPDATE
      SET child_count = hivemind_app.__post_children.child_count + excluded.child_count
    ;

    __depth := __depth -1;
  END LOOP;

  DROP TABLE hivemind_app.__post_tree;
  -- The ranges' plans estimate their share of the table from these statistics.
  ANALYZE hivemind_app.__post_children;

RESET work_mem;

END;

$BODY$
;

--- The posts with ids in _first_id .. _last_id. Writes no column but those of the
--- recomputation and no row outside the range, so ranges run at the same time
--- never wait on each other's rows. hive_votes is read through an index on its
--- post_id (DbState restores hive_votes' indexes before finalization), hive_posts and
--- __post_children by their primary keys: an initial sync runs this before
--- hive_posts' registered indexes are restored (DbState defers them), so it must not
--- depend on any of them.
CREATE OR REPLACE FUNCTION hivemind_app.recalculate_posts_votes_and_children(_first_id INT, _last_id INT)
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
BEGIN
SET LOCAL work_mem='512MB';
-- A generic plan would estimate every range at the default selectivity of a range
-- condition, whatever its width.
SET LOCAL plan_cache_mode = force_custom_plan;

  -- Vote aggregates go to posts with votes that are not deleted, `children` to
  -- posts with a count that differs; each keeps its old value elsewhere. A row
  -- none of whose values change is not written: a finalization re-run after an
  -- interruption finds hive_posts' indexes restored, and rewriting every row
  -- would insert each new version into all of them.
  -- Hash-free: hive_votes is read in post_id order and __post_children by its
  -- primary key, so a sorted aggregate and a merge full join need no memory. A
  -- hash aggregate holds about 430 bytes per voted post (tens of GB on mainnet),
  -- and the planner picks it whenever it underestimates the post count.
  SET LOCAL enable_hashagg = off;
  SET LOCAL enable_hashjoin = off;
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
          WHERE hv.post_id BETWEEN _first_id AND _last_id
          GROUP BY hv.post_id
        ) as votes_rshares
      FULL JOIN
        (
          SELECT pc.id, pc.child_count
          FROM hivemind_app.__post_children pc
          WHERE pc.id BETWEEN _first_id AND _last_id
        ) as pc ON pc.id = votes_rshares.post_id
    ) as s
  WHERE hp.id = s.post_id
  AND hp.id BETWEEN _first_id AND _last_id
  AND (
    s.child_count != hp.children
    OR (
      s.voted AND hp.counter_deleted = 0
      AND (hp.abs_rshares, hp.vote_rshares, hp.total_votes, hp.net_votes, hp.sc_hot, hp.sc_trend)
        IS DISTINCT FROM
        (
            s.abs_rshares
          , s.rshares
          , s.total_votes
          , s.net_votes
          , CASE WHEN hp.is_paidout OR hp.parent_id > 0 THEN 0 ELSE hivemind_app.calculate_hot( s.rshares, hp.created_at) END
          , CASE WHEN hp.is_paidout OR hp.parent_id > 0 THEN 0 ELSE hivemind_app.calculate_trending( s.rshares, hp.created_at) END
        )
    )
  );

RESET enable_hashjoin;
RESET enable_hashagg;
RESET plan_cache_mode;
RESET work_mem;

END;

$BODY$
;

CREATE OR REPLACE FUNCTION hivemind_app.recalculate_all_posts_votes_and_children()
RETURNS VOID
LANGUAGE 'plpgsql'
VOLATILE
AS
$BODY$
BEGIN
  PERFORM hivemind_app.prepare_posts_children();
  PERFORM hivemind_app.recalculate_posts_votes_and_children(0, 2147483647);
  TRUNCATE TABLE hivemind_app.__post_children;
END;

$BODY$
;
