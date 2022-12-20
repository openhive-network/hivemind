DROP MATERIALIZED VIEW IF EXISTS hivemind_app.payout_stats_view;

CREATE MATERIALIZED VIEW hivemind_app.payout_stats_view AS
  SELECT
      hp1.community_id,
      ha.name AS author,
      SUM( hp1.payout + hp1.pending_payout ) AS payout,
      COUNT(*) AS posts,
      NULL AS authors
  FROM hivemind_app.hive_posts hp1
      JOIN hivemind_app.hive_accounts ha ON ha.id = hp1.author_id
  WHERE hp1.counter_deleted = 0 AND NOT hp1.is_paidout AND hp1.id != 0
  GROUP BY community_id, author

  UNION ALL

  SELECT
        hp2.community_id,
        NULL AS author,
        SUM( hp2.payout + hp2.pending_payout ) AS payout,
        COUNT(*) AS posts,
        COUNT(DISTINCT(author_id)) AS authors
  FROM hivemind_app.hive_posts hp2
  WHERE hp2.counter_deleted = 0 AND NOT hp2.is_paidout AND hp2.id != 0
  GROUP BY community_id

WITH DATA
;

CREATE UNIQUE INDEX IF NOT EXISTS payout_stats_view_ix1 ON hivemind_app.payout_stats_view (community_id, author );
CREATE INDEX IF NOT EXISTS payout_stats_view_ix2 ON hivemind_app.payout_stats_view (community_id, author, payout);
