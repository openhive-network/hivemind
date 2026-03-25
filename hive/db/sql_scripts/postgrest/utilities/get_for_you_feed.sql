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
_cutoff_followed INT;
_cutoff_discovery INT;
_cutoff_affinity INT;
_followed_slots INT;
_discovery_slots INT;
_result JSONB;

-- Signal weights (followed)
_w_affinity INT := 50;
_w_follow_velocity INT := 20;
_w_follow_quality INT := 10;

-- Signal weights (discovery)
_w_disc_velocity INT := 30;
_w_disc_quality INT := 15;
_thread_ratio_cap FLOAT := 10.0;
_w_social_proof INT := 25;
_w_community_sub INT := 40;
_w_community_active INT := 30;
_w_tag_affinity INT := 5;
_max_tag_score INT := 50;
_w_mutual_follows INT := 15;

-- General
_freshness_max_hours INT := 100;
_min_discovery_payout FLOAT := 1.0;

-- Diversity
_max_per_author_followed INT := 2;
_max_per_author_discovery INT := 1;
_max_per_community INT := 3;
_max_tags INT := 50;
_discovery_pool_size INT := 1000;

-- Blacklisted thread container accounts
_blacklisted_accounts TEXT[] := ARRAY['ecency.waves', 'peak.snaps', 'leothreads'];

BEGIN
  _cutoff_followed  = hivemind_app.block_before_head('1 month');
  _cutoff_discovery = hivemind_app.block_before_head('14 days');
  _cutoff_affinity  = hivemind_app.block_before_head('90 days');

  -- Split limit into followed/discovery slots (50/50)
  _followed_slots  = (_limit + 1) / 2;
  _discovery_slots = _limit / 2;

  _result = (
    SELECT jsonb_agg(
      hivemind_postgrest_utilities.create_bridge_post_object(
        _observer_id, row, 0, NULL, False, True
      )
    ) FROM (
      WITH
      -- =============================================================
      -- USER'S SOCIAL GRAPH
      -- =============================================================
      my_following AS MATERIALIZED (
        SELECT f.following AS account_id
        FROM hivemind_app.follows f
        WHERE f.follower = _account_id
      ),

      mutuals AS MATERIALIZED (
        SELECT mf.account_id
        FROM my_following mf
        JOIN hivemind_app.follows f2 ON f2.follower = mf.account_id
          AND f2.following = _account_id
      ),

      my_communities AS MATERIALIZED (
        SELECT hs.community_id
        FROM hivemind_app.hive_subscriptions hs
        WHERE hs.account_id = _account_id
      ),

      -- =============================================================
      -- SIGNAL: Author affinity (who does this user comment on?)
      -- =============================================================
      author_affinity AS MATERIALIZED (
        SELECT
          pp.author_id,
          COUNT(*) AS interaction_count
        FROM hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_posts pp ON pp.id = hp.parent_id
        WHERE hp.author_id = _account_id
          AND hp.depth > 0
          AND hp.counter_deleted = 0
          AND hp.block_num > _cutoff_affinity
        GROUP BY pp.author_id
      ),

      -- =============================================================
      -- SIGNAL: Community activity (communities user comments in)
      -- =============================================================
      active_communities AS MATERIALIZED (
        SELECT
          pp.community_id,
          COUNT(*) AS comment_count
        FROM hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_posts pp ON pp.id = hp.parent_id
        WHERE hp.author_id = _account_id
          AND hp.depth > 0
          AND hp.counter_deleted = 0
          AND hp.block_num > _cutoff_affinity
          AND pp.community_id IS NOT NULL
        GROUP BY pp.community_id
      ),

      -- =============================================================
      -- SIGNAL: Tag affinity (tags on posts the user comments on)
      -- =============================================================
      user_active_tags AS MATERIALIZED (
        SELECT
          htd.id AS tag_id,
          COUNT(*) AS tag_weight
        FROM hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.parent_id
        JOIN hivemind_app.hive_tag_data htd ON htd.id = hpt.tag_id
        WHERE hp.author_id = _account_id
          AND hp.depth > 0
          AND hp.counter_deleted = 0
          AND hp.block_num > _cutoff_affinity
          AND htd.tag NOT LIKE 'hive-%'
        GROUP BY htd.id
        ORDER BY tag_weight DESC
        LIMIT _max_tags
      ),

      -- =============================================================
      -- FOLLOWED POSTS: scored by affinity + engagement + quality
      -- =============================================================
      followed_scored AS (
        SELECT
          hfc.post_id AS id,
          hp.author_id,
          (
            COALESCE(aa.interaction_count, 0) * _w_affinity
            + LN(1 + hp.children::FLOAT / GREATEST(1, EXTRACT(EPOCH FROM (NOW() - hp.created_at)) / 3600))
              * _w_follow_velocity
              * CASE WHEN GREATEST(hp.payout, hp.pending_payout) > 0
                     AND hp.children::FLOAT / GREATEST(hp.payout, hp.pending_payout)::FLOAT > _thread_ratio_cap
                THEN 0.1 ELSE 1.0 END
            + LN(1 + GREATEST(hp.payout, hp.pending_payout)::FLOAT)
              * _w_follow_quality
            + GREATEST(0, _freshness_max_hours
              - EXTRACT(EPOCH FROM (NOW() - hp.created_at)) / 3600)
          )::FLOAT AS score
        FROM my_following mf
        JOIN hivemind_app.hive_feed_cache hfc ON hfc.account_id = mf.account_id
          AND hfc.block_num > _cutoff_followed
        JOIN hivemind_app.hive_posts hp ON hp.id = hfc.post_id
          AND hp.counter_deleted = 0
          AND hp.depth = 0
        LEFT JOIN author_affinity aa ON aa.author_id = mf.account_id
        WHERE (_post_id = 0 OR hfc.post_id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hfc.account_id
          ))
        GROUP BY hfc.post_id, hp.author_id, hp.children, hp.created_at, hp.payout, hp.pending_payout, aa.interaction_count
      ),

      followed_ranked AS (
        SELECT id, author_id, score,
          ROW_NUMBER() OVER (PARTITION BY author_id ORDER BY score DESC, id DESC) AS author_rn
        FROM followed_scored
      ),

      followed_final AS (
        SELECT id, score
        FROM followed_ranked
        WHERE author_rn <= _max_per_author_followed
        ORDER BY score DESC, id DESC
        LIMIT _followed_slots
      ),

      -- =============================================================
      -- DISCOVERY CANDIDATE POOL
      -- =============================================================

      -- Source 1: Top trending — broad baseline
      src_trending AS (
        SELECT hp.id
        FROM hivemind_app.hive_posts hp
        WHERE hp.depth = 0
          AND hp.counter_deleted = 0
          AND NOT hp.is_paidout
          AND hp.block_num > _cutoff_discovery
          AND hp.author_id != _account_id
          AND hp.author_id NOT IN (SELECT account_id FROM my_following)
          AND (_post_id = 0 OR hp.id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
        ORDER BY hp.sc_trend DESC
        LIMIT _discovery_pool_size
      ),

      -- Source 2: Posts from subscribed communities
      src_community_sub AS (
        SELECT hp.id
        FROM my_communities mc
        JOIN hivemind_app.hive_posts hp ON hp.community_id = mc.community_id
          AND hp.depth = 0
          AND hp.counter_deleted = 0
          AND NOT hp.is_paidout
          AND hp.block_num > _cutoff_discovery
        WHERE hp.author_id != _account_id
          AND hp.author_id NOT IN (SELECT account_id FROM my_following)
          AND (_post_id = 0 OR hp.id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
        ORDER BY hp.sc_trend DESC
        LIMIT _discovery_pool_size
      ),

      -- Source 3: Posts from communities the user actively comments in
      src_community_active AS (
        SELECT hp.id
        FROM active_communities ac
        JOIN hivemind_app.hive_posts hp ON hp.community_id = ac.community_id
          AND hp.depth = 0
          AND hp.counter_deleted = 0
          AND NOT hp.is_paidout
          AND hp.block_num > _cutoff_discovery
        WHERE hp.author_id != _account_id
          AND hp.author_id NOT IN (SELECT account_id FROM my_following)
          AND hp.community_id NOT IN (SELECT community_id FROM my_communities)
          AND (_post_id = 0 OR hp.id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
        ORDER BY hp.sc_trend DESC
        LIMIT _discovery_pool_size
      ),

      -- Source 4: Posts matching user's active tags
      src_tag_match AS (
        SELECT DISTINCT hp.id
        FROM user_active_tags uat
        JOIN hivemind_app.hive_post_tags hpt ON hpt.tag_id = uat.tag_id
        JOIN hivemind_app.hive_posts hp ON hp.id = hpt.post_id
          AND hp.depth = 0
          AND hp.counter_deleted = 0
          AND NOT hp.is_paidout
          AND hp.block_num > _cutoff_discovery
        WHERE hp.author_id != _account_id
          AND hp.author_id NOT IN (SELECT account_id FROM my_following)
          AND (_post_id = 0 OR hp.id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
      ),

      -- Source 5: Posts by authors that mutuals follow (2-hop discovery)
      src_mutual_follows AS (
        SELECT DISTINCT hp.id
        FROM mutuals m
        JOIN hivemind_app.follows mff ON mff.follower = m.account_id
        JOIN hivemind_app.hive_posts hp ON hp.author_id = mff.following
          AND hp.depth = 0
          AND hp.counter_deleted = 0
          AND NOT hp.is_paidout
          AND hp.block_num > _cutoff_discovery
        WHERE mff.following NOT IN (SELECT account_id FROM my_following)
          AND mff.following != _account_id
          AND (_post_id = 0 OR hp.id < _post_id)
          AND (_observer_id = 0 OR NOT EXISTS (
            SELECT 1 FROM hivemind_app.muted_accounts_by_id_view
            WHERE observer_id = _observer_id AND muted_id = hp.author_id
          ))
      ),

      -- Merge all discovery candidate IDs (deduplicated)
      discovery_ids AS MATERIALIZED (
        SELECT DISTINCT id FROM (
          SELECT id FROM src_trending
          UNION ALL
          SELECT id FROM src_community_sub
          UNION ALL
          SELECT id FROM src_community_active
          UNION ALL
          SELECT id FROM src_tag_match
          UNION ALL
          SELECT id FROM src_mutual_follows
        ) all_sources
        WHERE id NOT IN (SELECT id FROM followed_final)
      ),

      -- Hydrate candidates with post data + minimum payout filter + blacklist
      discovery_candidates AS (
        SELECT
          hp.id,
          hp.author_id,
          hp.community_id,
          hp.children,
          hp.created_at,
          hp.payout,
          hp.pending_payout,
          hp.sc_trend
        FROM discovery_ids di
        JOIN hivemind_app.hive_posts hp ON hp.id = di.id
        JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
        WHERE GREATEST(hp.payout, hp.pending_payout) >= _min_discovery_payout
          AND ha.name != ALL(_blacklisted_accounts)
      ),

      -- =============================================================
      -- COMPUTE ALL SIGNALS PER DISCOVERY CANDIDATE
      -- =============================================================

      -- Social proof: how many mutuals commented on each candidate?
      social_proof AS (
        SELECT
          cp.parent_id AS post_id,
          COUNT(DISTINCT cp.author_id) AS mutual_count
        FROM hivemind_app.hive_posts cp
        WHERE cp.author_id IN (SELECT account_id FROM mutuals)
          AND cp.depth > 0
          AND cp.counter_deleted = 0
          AND cp.parent_id IN (SELECT id FROM discovery_ids)
          AND cp.block_num > _cutoff_discovery
        GROUP BY cp.parent_id
      ),

      -- Tag match score per candidate
      tag_match_score AS (
        SELECT
          hpt.post_id,
          SUM(uat.tag_weight) AS total_tag_weight
        FROM user_active_tags uat
        JOIN hivemind_app.hive_post_tags hpt ON hpt.tag_id = uat.tag_id
        WHERE hpt.post_id IN (SELECT id FROM discovery_ids)
        GROUP BY hpt.post_id
      ),

      -- Mutual follows count: how many mutuals follow this post's author?
      mutual_follow_count AS (
        SELECT
          dc.id AS post_id,
          COUNT(DISTINCT m.account_id) AS mutual_count
        FROM discovery_candidates dc
        JOIN hivemind_app.follows mff ON mff.following = dc.author_id
        JOIN mutuals m ON m.account_id = mff.follower
        GROUP BY dc.id
      ),

      -- Author affinity for discovery
      discovery_author_affinity AS (
        SELECT
          dc.id AS post_id,
          COALESCE(aa.interaction_count, 0) AS interaction_count
        FROM discovery_candidates dc
        LEFT JOIN author_affinity aa ON aa.author_id = dc.author_id
      ),

      -- =============================================================
      -- SCORE DISCOVERY CANDIDATES
      -- =============================================================
      discovery_scored AS (
        SELECT
          dc.id,
          dc.author_id,
          dc.community_id,
          (
            -- Comment velocity (log-scaled, thread-penalized)
            LN(1 + dc.children::FLOAT / GREATEST(1, EXTRACT(EPOCH FROM (NOW() - dc.created_at)) / 3600))
              * _w_disc_velocity
              * CASE WHEN GREATEST(dc.payout, dc.pending_payout) > 0
                     AND dc.children::FLOAT / GREATEST(dc.payout, dc.pending_payout)::FLOAT > _thread_ratio_cap
                THEN 0.1 ELSE 1.0 END
            -- Payout quality (log-scaled)
            + LN(1 + GREATEST(dc.payout, dc.pending_payout)::FLOAT)
              * _w_disc_quality
            -- Community subscription boost
            + CASE WHEN dc.community_id IN (SELECT community_id FROM my_communities)
                THEN _w_community_sub ELSE 0 END
            -- Community activity boost
            + CASE WHEN dc.community_id IN (SELECT community_id FROM active_communities)
                    AND dc.community_id NOT IN (SELECT community_id FROM my_communities)
                THEN _w_community_active ELSE 0 END
            -- Tag affinity (capped)
            + LEAST(
                COALESCE(tms.total_tag_weight, 0) * _w_tag_affinity,
                _max_tag_score
              )
            -- Social proof (mutuals commented)
            + COALESCE(sp.mutual_count, 0) * _w_social_proof
            -- Mutual follows (mutuals follow this author)
            + COALESCE(mfc.mutual_count, 0) * _w_mutual_follows
            -- Author affinity
            + COALESCE(daa.interaction_count, 0) * _w_affinity
            -- Freshness
            + GREATEST(0, _freshness_max_hours
              - EXTRACT(EPOCH FROM (NOW() - dc.created_at)) / 3600)
          )::FLOAT AS score
        FROM discovery_candidates dc
        LEFT JOIN social_proof sp ON sp.post_id = dc.id
        LEFT JOIN tag_match_score tms ON tms.post_id = dc.id
        LEFT JOIN mutual_follow_count mfc ON mfc.post_id = dc.id
        LEFT JOIN discovery_author_affinity daa ON daa.post_id = dc.id
      ),

      -- Diversity: max N posts per author AND per community
      discovery_ranked AS (
        SELECT id, author_id, score, community_id,
          ROW_NUMBER() OVER (PARTITION BY author_id ORDER BY score DESC, id DESC) AS author_rn,
          ROW_NUMBER() OVER (PARTITION BY community_id ORDER BY score DESC, id DESC) AS community_rn
        FROM discovery_scored
      ),

      discovery_final AS (
        SELECT id, score
        FROM discovery_ranked
        WHERE author_rn <= _max_per_author_discovery
          AND (community_id IS NULL OR community_rn <= _max_per_community)
        ORDER BY score DESC, id DESC
        LIMIT _discovery_slots
      ),

      -- =============================================================
      -- FINAL: Interleave followed + discovery (50/50)
      -- =============================================================
      interleaved AS (
        SELECT id, score, 'followed' AS source,
          ROW_NUMBER() OVER (ORDER BY score DESC, id DESC) AS rn
        FROM followed_final
        UNION ALL
        SELECT id, score, 'discovery' AS source,
          ROW_NUMBER() OVER (ORDER BY score DESC, id DESC) AS rn
        FROM discovery_final
      ),

      final_feed AS (
        SELECT
          id, score, source,
          ROW_NUMBER() OVER (
            ORDER BY
              CASE source
                WHEN 'followed'  THEN rn
                WHEN 'discovery' THEN rn
              END,
              CASE source WHEN 'followed' THEN 1 ELSE 2 END,
              score DESC
          ) AS feed_position
        FROM interleaved
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
      ORDER BY ff.feed_position
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;
