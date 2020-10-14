DROP FUNCTION IF EXISTS public.update_hive_posts_children_count;
CREATE OR REPLACE FUNCTION public.update_hive_posts_children_count(in _first_block INTEGER, in _last_block INTEGER)
  RETURNS void
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
BEGIN
UPDATE hive_posts uhp
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
  FROM hive_posts h1
  WHERE h1.block_num BETWEEN _first_block AND _last_block OR h1.block_num_created BETWEEN _first_block AND _last_block
  ORDER BY h1.depth DESC
  ) s
  UNION ALL
  SELECT
    p.parent_id as queried_parent
  , p.id as id
  , p.depth as depth
  , tblChild.delta as delta
  FROM hive_posts p
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
