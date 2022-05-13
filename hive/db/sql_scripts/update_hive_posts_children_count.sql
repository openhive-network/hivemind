DROP FUNCTION IF EXISTS hivemind_app.update_hive_posts_children_count;
CREATE OR REPLACE FUNCTION hivemind_app.update_hive_posts_children_count(in _first_block INTEGER, in _last_block INTEGER)
  RETURNS void
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
BEGIN
UPDATE hivemind_app.hive_posts uhp
SET children = data_source.delta + uhp.children
FROM
(
WITH recursive tblChild AS
(
  SELECT
    s.queried_parent as queried_parent
  , s.id as id
  , s.depth as depth
  , (s.delta_created + s.delta_deleted) as delta
  FROM
  (
  SELECT
      h1.parent_id AS queried_parent
    , h1.id as id
    , h1.depth as depth
    , (
      CASE
        WHEN (h1.block_num_created BETWEEN _first_block AND _last_block ) THEN 1
        ELSE 0
      END
      ) as delta_created
    , (
      CASE
        -- assumption that deleted post cannot be edited
        WHEN h1.counter_deleted != 0 THEN -1
        ELSE 0
      END
      ) as delta_deleted
  FROM hivemind_app.hive_posts h1
  WHERE h1.block_num BETWEEN _first_block AND _last_block OR h1.block_num_created BETWEEN _first_block AND _last_block
  ORDER BY h1.depth DESC
  ) s
  UNION ALL
  SELECT
    p.parent_id as queried_parent
  , p.id as id
  , p.depth as depth
  , tblChild.delta as delta
  FROM hivemind_app.hive_posts p
  JOIN tblChild  ON p.id = tblChild.queried_parent
  WHERE p.depth < tblChild.depth
)
SELECT
    queried_parent
  , SUM(delta) as delta
FROM
  tblChild
GROUP BY queried_parent
) data_source
WHERE uhp.id = data_source.queried_parent
;
END
$BODY$;

DROP FUNCTION IF EXISTS hivemind_app.update_all_hive_posts_children_count;
CREATE OR REPLACE FUNCTION hivemind_app.update_all_hive_posts_children_count()
  RETURNS void
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
declare __depth INT;
BEGIN
  SELECT MAX(hp.depth) into __depth FROM hivemind_app.hive_posts hp ;

  CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app.__post_children
  (
    id INT NOT NULL,
    child_count INT NOT NULL,
    CONSTRAINT __post_children_pkey PRIMARY KEY (id)
  );

  TRUNCATE TABLE hivemind_app.__post_children;
  
  WHILE __depth >= 0 LOOP
    INSERT INTO hivemind_app.__post_children
    (id, child_count)
      SELECT
        h1.parent_id AS queried_parent,
        SUM(COALESCE((SELECT pc.child_count FROM hivemind_app.__post_children pc WHERE pc.id = h1.id),
                      0
                    ) + 1
        ) AS count
      FROM hivemind_app.hive_posts h1
      WHERE (h1.parent_id != 0 OR __depth = 0) AND h1.counter_deleted = 0 AND h1.id != 0 AND h1.depth = __depth
      GROUP BY h1.parent_id

    ON CONFLICT ON CONSTRAINT __post_children_pkey DO UPDATE
      SET child_count = hivemind_app.__post_children.child_count + excluded.child_count
    ;

    __depth := __depth -1;
  END LOOP;

  UPDATE hivemind_app.hive_posts uhp
  SET children = s.child_count
  FROM
  hivemind_app.__post_children s
  WHERE s.id = uhp.id and s.child_count != uhp.children
  ;
  
  TRUNCATE TABLE hivemind_app.__post_children;

END
$BODY$;
