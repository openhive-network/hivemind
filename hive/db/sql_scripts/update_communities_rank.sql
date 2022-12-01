DROP FUNCTION IF EXISTS hivemind_app.update_communities_posts_data_and_rank;
CREATE FUNCTION hivemind_app.update_communities_posts_data_and_rank()
RETURNS void
AS
$function$
UPDATE hivemind_app.hive_communities hc SET
  num_pending = cr.posts,
  sum_pending = cr.payouts,
  num_authors = cr.authors,
  rank = cr.rank
FROM
(
    SELECT
      c.id as id,
      ROW_NUMBER() OVER ( ORDER BY COALESCE(p.payouts, 0) DESC, COALESCE(p.authors, 0) DESC, COALESCE(p.posts, 0) DESC, c.subscribers DESC, (CASE WHEN c.title = '' THEN 1 ELSE 0 END), c.id DESC ) as rank,
      COALESCE(p.posts, 0) as posts,
      COALESCE(p.payouts, 0) as payouts,
      COALESCE(p.authors, 0) as authors
    FROM hivemind_app.hive_communities c
    LEFT JOIN (
              SELECT hp.community_id,
                     COUNT(*) posts,
                     ROUND(SUM(hp.pending_payout)) payouts,
                     COUNT(DISTINCT hp.author_id) authors
                FROM hivemind_app.hive_posts hp
               WHERE community_id IS NOT NULL
                 AND NOT hp.is_paidout
                 AND hp.counter_deleted = 0
            GROUP BY hp.community_id
         ) p
         ON p.community_id = c.id
) as cr
WHERE hc.id = cr.id;
$function$
language sql;
