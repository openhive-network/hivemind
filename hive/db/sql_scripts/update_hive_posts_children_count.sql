DROP FUNCTION IF EXISTS public.update_hive_posts_children_count(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.update_hive_posts_children_count(in _first_block INTEGER, in _last_block INTEGER)
    RETURNS void
    LANGUAGE SQL
    VOLATILE
AS $BODY$
UPDATE hive_posts uhp
SET children = data_source.children_count
FROM
(
  WITH recursive tblChild AS
  (
    SELECT s.queried_parent, s.id
    FROM
    (SELECT h1.Parent_Id AS queried_parent, h1.id
      FROM hive_posts h1
      WHERE h1.depth > 0 AND h1.counter_deleted = 0
            AND h1.block_num BETWEEN _first_block AND _last_block
      ORDER BY h1.depth DESC
    ) s
    UNION ALL
    SELECT tblChild.queried_parent, p.id FROM hive_posts p
    JOIN tblChild  ON p.Parent_Id = tblChild.Id
    WHERE p.counter_deleted = 0
  )
  SELECT queried_parent, cast(count(1) AS int) AS children_count
  FROM tblChild
  GROUP BY queried_parent
) data_source
WHERE uhp.id = data_source.queried_parent
;
$BODY$;