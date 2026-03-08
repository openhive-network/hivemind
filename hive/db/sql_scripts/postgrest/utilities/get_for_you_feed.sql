DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_for_you_feed;
CREATE FUNCTION hivemind_postgrest_utilities.get_for_you_feed(
  IN _account_id INT,
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT
)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_cutoff_1month INT;
_cutoff_2weeks INT;
_cutoff_3months INT;
_result JSONB;
BEGIN
  _cutoff_1month = hivemind_app.block_before_head('1 month');
  _cutoff_2weeks = hivemind_app.block_before_head('14 days');
  _cutoff_3months = hivemind_app.block_before_head('90 days');

  _result = (
    SELECT jsonb_agg(
      hivemind_postgrest_utilities.create_bridge_post_object(
        _observer_id, row, 0, NULL, False, True
      )
    ) FROM (
      WITH
      mutuals AS (
        SELECT f1.following AS account_id
        FROM hivemind_app.follows f1
        JOIN hivemind_app.follows f2 ON f1.following = f2.follower AND f2.following = _account_id
        WHERE f1.follower = _account_id
      ),
      user_active_tags AS (
        SELECT
          htd.id AS tag_id,
          COUNT(*) AS tag_weight
        FROM hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.parent_id
        JOIN hivemind_app.hive_tag_data htd ON htd.id = hpt.tag_id
        WHERE hp.author_id = _account_id
          AND hp.depth > 0
          AND hp.counter_deleted = 0
          AND hp.block_num > _cutoff_3months
          AND htd.tag NOT LIKE 'hive-%'
        GROUP BY htd.id
        ORDER BY tag_weight DESC
        LIMIT 50
      ),
      followed_posts AS (
        SELECT
          hfc.post_id AS id,
          (1000 + GREATEST(0, 100 - EXTRACT(EPOCH FROM (NOW() - hp.created_at)) / 3600))::FLOAT AS score
        FROM hivemind_app.hive_feed_cache hfc
        JOIN hivemind_app.follows f ON hfc.account_id = f.following
        JOIN hivemind_app.hive_posts hp ON hp.id = hfc.post_id
        WHERE f.follower = _account_id
          AND hfc.block_num > _cutoff_1month
          AND hp.counter_deleted = 0
          AND hp.depth = 0
          AND (_post_id = 0 OR hfc.post_id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hfc.account_id
          ))
        GROUP BY hfc.post_id, hp.created_at
      ),
      mutual_commented AS (
        SELECT
          cp.parent_id AS id,
          COUNT(DISTINCT cm.account_id)::FLOAT * 15 AS signal_score
        FROM mutuals cm
        JOIN hivemind_app.hive_posts cp ON cp.author_id = cm.account_id
          AND cp.depth > 0
          AND cp.counter_deleted = 0
          AND cp.block_num > _cutoff_2weeks
        JOIN hivemind_app.hive_posts pp ON pp.id = cp.parent_id
          AND pp.depth = 0
          AND pp.counter_deleted = 0
        WHERE pp.author_id NOT IN (SELECT following FROM hivemind_app.follows WHERE follower = _account_id)
          AND (_post_id = 0 OR pp.id < _post_id)
        GROUP BY cp.parent_id
      ),
      mutual_follows_posts AS (
        SELECT
          hp.id,
          COUNT(DISTINCT mf.account_id)::FLOAT * 10 AS signal_score
        FROM mutuals mf
        JOIN hivemind_app.follows mff ON mff.follower = mf.account_id
        JOIN hivemind_app.hive_posts hp ON hp.author_id = mff.following
          AND hp.depth = 0
          AND hp.counter_deleted = 0
          AND hp.block_num > _cutoff_2weeks
        WHERE mff.following NOT IN (SELECT following FROM hivemind_app.follows WHERE follower = _account_id)
          AND mff.following != _account_id
          AND (_post_id = 0 OR hp.id < _post_id)
        GROUP BY hp.id
      ),
      tag_affinity AS (
        SELECT
          hp.id,
          SUM(uat.tag_weight * 2 + hp.sc_trend * 5)::FLOAT AS signal_score
        FROM user_active_tags uat
        JOIN hivemind_app.hive_post_tags hpt ON hpt.tag_id = uat.tag_id
        JOIN hivemind_app.hive_posts hp ON hp.id = hpt.post_id
          AND hp.depth = 0
          AND hp.counter_deleted = 0
          AND hp.block_num > _cutoff_2weeks
        WHERE hp.author_id NOT IN (SELECT following FROM hivemind_app.follows WHERE follower = _account_id)
          AND hp.author_id != _account_id
          AND (_post_id = 0 OR hp.id < _post_id)
        GROUP BY hp.id
      ),
      trending_posts AS (
        SELECT
          hp.id,
          (hp.sc_trend * 8)::FLOAT AS signal_score
        FROM hivemind_app.live_posts_view hp
        WHERE NOT hp.is_paidout
          AND hp.block_num > _cutoff_2weeks
          AND hp.author_id NOT IN (SELECT following FROM hivemind_app.follows WHERE follower = _account_id)
          AND hp.author_id != _account_id
          AND (_post_id = 0 OR hp.id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
        ORDER BY hp.sc_trend DESC
        LIMIT _limit * 3
      ),
      community_sub_posts AS (
        SELECT
          hp.id,
          (50 + hp.sc_trend * 3)::FLOAT AS signal_score
        FROM hivemind_app.hive_subscriptions hs
        JOIN hivemind_app.hive_posts hp ON hp.community_id = hs.community_id
          AND hp.depth = 0
          AND hp.counter_deleted = 0
          AND hp.block_num > _cutoff_2weeks
        WHERE hs.account_id = _account_id
          AND hp.author_id NOT IN (SELECT following FROM hivemind_app.follows WHERE follower = _account_id)
          AND hp.author_id != _account_id
          AND (_post_id = 0 OR hp.id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
      ),
      discovery_scored AS (
        SELECT
          ds.id,
          SUM(ds.signal_score)
            + GREATEST(0, 100 - EXTRACT(EPOCH FROM (NOW() - hp.created_at)) / 3600) AS score
        FROM (
          SELECT id, signal_score FROM mutual_commented
          UNION ALL
          SELECT id, signal_score FROM mutual_follows_posts
          UNION ALL
          SELECT id, signal_score FROM tag_affinity
          UNION ALL
          SELECT id, signal_score FROM trending_posts
          UNION ALL
          SELECT id, signal_score FROM community_sub_posts
        ) ds
        JOIN hivemind_app.hive_posts hp ON hp.id = ds.id
        WHERE ds.id NOT IN (SELECT id FROM followed_posts)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
        GROUP BY ds.id, hp.created_at
      ),
      combined_feed AS (
        SELECT id, score FROM followed_posts
        UNION ALL
        SELECT id, score FROM discovery_scored
      ),
      final_feed AS (
        SELECT cf.id, MAX(cf.score) AS score
        FROM combined_feed cf
        GROUP BY cf.id
        ORDER BY score DESC, cf.id DESC
        LIMIT _limit
      )
      SELECT
        hp.id,
        hp.author,
        hp.parent_author,
        hp.author_rep,
        hp.root_title,
        hp.beneficiaries,
        hp.max_accepted_payout,
        hp.percent_hbd,
        hp.url,
        hp.permlink,
        hp.parent_permlink_or_category,
        hp.title,
        hp.body,
        hp.category,
        hp.depth,
        hp.payout,
        hp.pending_payout,
        hp.payout_at,
        hp.is_paidout,
        hp.children,
        hp.votes,
        hp.created_at,
        hp.updated_at,
        hp.rshares,
        hp.abs_rshares,
        hp.json,
        hp.is_hidden,
        hp.is_grayed,
        hp.total_votes,
        hp.sc_trend,
        hp.role_title,
        hp.community_title,
        hp.role_id,
        hp.is_pinned,
        hp.curator_payout_value,
        hp.is_muted,
        hp.source AS blacklists,
        hp.muted_reasons
      FROM final_feed ff,
      LATERAL hivemind_app.get_full_post_view_by_id(ff.id, _observer_id) hp
      ORDER BY ff.score DESC, ff.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;
