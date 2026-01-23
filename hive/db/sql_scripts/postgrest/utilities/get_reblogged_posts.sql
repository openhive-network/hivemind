-- Utility functions for /blog/reblogs REST endpoint
-- These functions return lightweight reblog status for posts matching ranked posts criteria

-- Define the return type for reblog status (must be created before the functions that use it)
DROP TYPE IF EXISTS hivemind_endpoints.reblog_status CASCADE;
CREATE TYPE hivemind_endpoints.reblog_status AS (
    post_id INT,
    author TEXT,
    permlink TEXT,
    reblogged BOOLEAN
);

-- Internal helper function that contains all the common logic
-- The 4 public functions call this with different filter parameters
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_internal;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_internal(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type,
  IN _community_id INT,           -- Filter by specific community (NULL = no filter)
  IN _tag_id INT,                 -- Filter by specific tag (NULL = no filter)
  IN _filter_observer_communities BOOLEAN  -- Filter by observer's subscribed communities
)
RETURNS SETOF hivemind_endpoints.reblog_status
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _trending_limit FLOAT;
  _hot_limit FLOAT;
  _payout_limit hivemind_app.hive_posts.payout%TYPE;
BEGIN
  -- Get pagination limits from start post if specified
  IF _post_id <> 0 THEN
    SELECT sc_trend, sc_hot, payout INTO _trending_limit, _hot_limit, _payout_limit
    FROM hivemind_app.hive_posts WHERE id = _post_id;
  END IF;

  RETURN QUERY
    SELECT
      posts.id::INT AS post_id,
      ha.name::TEXT AS author,
      hpd.permlink::TEXT AS permlink,
      (hr.post_id IS NOT NULL) AS reblogged  -- LEFT JOIN is more efficient than correlated EXISTS
    FROM (
      SELECT hp.id, hp.author_id, hp.permlink_id
      FROM hivemind_app.live_posts_comments_view hp
      JOIN hivemind_app.hive_accounts_view hav ON hav.id = hp.author_id
      -- Conditional JOINs based on filter type
      LEFT JOIN hivemind_app.hive_subscriptions hs
        ON _filter_observer_communities AND hs.community_id = hp.community_id AND hs.account_id = _observer_id
      LEFT JOIN hivemind_app.hive_post_tags hpt
        ON _tag_id IS NOT NULL AND hpt.post_id = hp.id AND hpt.tag_id = _tag_id
      WHERE
        -- Apply filter based on parameters
        (_community_id IS NULL OR hp.community_id = _community_id)
        AND (NOT _filter_observer_communities OR hs.community_id IS NOT NULL)
        AND (_tag_id IS NULL OR hpt.tag_id IS NOT NULL)
        -- Sort-specific conditions
        AND CASE _sort_type
          WHEN 'trending' THEN hp.depth = 0 AND NOT hp.is_paidout
            AND (_post_id = 0 OR hp.sc_trend < _trending_limit OR (hp.sc_trend = _trending_limit AND hp.id < _post_id))
          WHEN 'hot' THEN hp.depth = 0 AND NOT hp.is_paidout
            AND (_post_id = 0 OR hp.sc_hot < _hot_limit OR (hp.sc_hot = _hot_limit AND hp.id < _post_id))
          WHEN 'created' THEN hp.depth = 0
            AND (_post_id = 0 OR hp.id < _post_id)
          WHEN 'payout' THEN hp.depth = 0 AND NOT hp.is_paidout
            AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'payout_comments' THEN hp.depth > 0 AND NOT hp.is_paidout
            AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'muted' THEN hp.depth = 0 AND hav.is_grayed AND NOT hp.is_paidout AND hp.payout > 0
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          ELSE True
        END
        -- Exclude muted authors
        AND NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id)
      ORDER BY
        CASE _sort_type
          WHEN 'trending' THEN hp.sc_trend
          WHEN 'hot' THEN hp.sc_hot
          WHEN 'payout' THEN hp.payout
          WHEN 'payout_comments' THEN hp.payout
          WHEN 'muted' THEN hp.payout
          ELSE NULL
        END DESC NULLS LAST,
        hp.id DESC
      LIMIT _limit
    ) posts
    JOIN hivemind_app.hive_accounts ha ON ha.id = posts.author_id
    JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = posts.permlink_id
    -- LEFT JOIN for reblog check instead of correlated EXISTS subquery
    LEFT JOIN hivemind_app.hive_reblogs hr ON hr.blogger_id = _observer_id AND hr.post_id = posts.id;
END
$$;

-- Public function: Get reblogged posts from all posts (no filter)
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_all;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_all(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS SETOF hivemind_endpoints.reblog_status
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_internal(
    _post_id, _observer_id, _limit, _sort_type,
    NULL,   -- _community_id: no community filter
    NULL,   -- _tag_id: no tag filter
    FALSE   -- _filter_observer_communities: don't filter by subscriptions
  );
END
$$;

-- Public function: Get reblogged posts from observer's subscribed communities
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_observer_communities(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS SETOF hivemind_endpoints.reblog_status
LANGUAGE 'plpgsql'
STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_internal(
    _post_id, _observer_id, _limit, _sort_type,
    NULL,   -- _community_id: no specific community
    NULL,   -- _tag_id: no tag filter
    TRUE    -- _filter_observer_communities: filter by subscriptions
  );
END
$$;

-- Public function: Get reblogged posts from a specific community
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_community;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_community(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _tag TEXT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS SETOF hivemind_endpoints.reblog_status
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _community_id INT;
BEGIN
  -- Look up community ID from name
  SELECT id INTO _community_id FROM hivemind_app.hive_communities WHERE name = _tag LIMIT 1;

  IF _community_id IS NULL THEN
    RETURN;  -- Community not found, return empty result
  END IF;

  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_internal(
    _post_id, _observer_id, _limit, _sort_type,
    _community_id,  -- Filter by this community
    NULL,           -- _tag_id: no tag filter
    FALSE           -- _filter_observer_communities: don't filter by subscriptions
  );
END
$$;

-- Public function: Get reblogged posts filtered by tag
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_tag(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _tag TEXT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS SETOF hivemind_endpoints.reblog_status
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _tag_id INT;
BEGIN
  -- Look up tag ID from name
  SELECT id INTO _tag_id FROM hivemind_app.hive_tag_data WHERE tag = _tag LIMIT 1;

  IF _tag_id IS NULL THEN
    RETURN;  -- Tag not found, return empty result
  END IF;

  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_reblogged_posts_internal(
    _post_id, _observer_id, _limit, _sort_type,
    NULL,     -- _community_id: no community filter
    _tag_id,  -- Filter by this tag
    FALSE     -- _filter_observer_communities: don't filter by subscriptions
  );
END
$$;
