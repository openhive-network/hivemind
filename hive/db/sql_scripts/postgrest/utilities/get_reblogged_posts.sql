-- Utility functions for hive.get_reblogged_by_account endpoint
-- These functions return lightweight reblog status for posts matching ranked posts criteria

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_all;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_all(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_hot_limit FLOAT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  -- Get pagination limits based on sort type
  IF _post_id <> 0 THEN
    SELECT sc_trend, sc_hot, payout INTO _trending_limit, _hot_limit, _payout_limit
    FROM hivemind_app.hive_posts WHERE id = _post_id;
  END IF;

  _result = (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'post_id', hp.id,
        'author', ha.name,
        'permlink', hpd.permlink,
        'reblogged', EXISTS (SELECT 1 FROM hivemind_app.hive_reblogs WHERE blogger_id = _observer_id AND post_id = hp.id)
      )
    ), '[]'::jsonb)
    FROM (
      SELECT hp.id, hp.author_id
      FROM hivemind_app.live_posts_view hp
      WHERE
        hp.depth = 0
        AND CASE _sort_type
          WHEN 'trending' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_trend < _trending_limit OR (hp.sc_trend = _trending_limit AND hp.id < _post_id))
          WHEN 'hot' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_hot < _hot_limit OR (hp.sc_hot = _hot_limit AND hp.id < _post_id))
          WHEN 'created' THEN (_post_id = 0 OR hp.id < _post_id)
          WHEN 'payout' THEN NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'payout_comments' THEN hp.depth > 0 AND NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'muted' THEN hp.is_grayed AND NOT hp.is_paidout AND hp.payout > 0
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          ELSE True
        END
        AND (_observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
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
    ) hp
    JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
    JOIN hivemind_app.hive_posts_data hpd ON hpd.id = hp.id
  );

  RETURN _result;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_observer_communities;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_observer_communities(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_hot_limit FLOAT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  -- Get pagination limits based on sort type
  IF _post_id <> 0 THEN
    SELECT sc_trend, sc_hot, payout INTO _trending_limit, _hot_limit, _payout_limit
    FROM hivemind_app.hive_posts WHERE id = _post_id;
  END IF;

  _result = (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'post_id', hp.id,
        'author', ha.name,
        'permlink', hpd.permlink,
        'reblogged', EXISTS (SELECT 1 FROM hivemind_app.hive_reblogs WHERE blogger_id = _observer_id AND post_id = hp.id)
      )
    ), '[]'::jsonb)
    FROM (
      SELECT hp.id, hp.author_id
      FROM hivemind_app.live_posts_view hp
      JOIN hivemind_app.hive_subscriptions hs ON hs.community_id = hp.community_id AND hs.account_id = _observer_id
      WHERE
        hp.depth = 0
        AND CASE _sort_type
          WHEN 'trending' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_trend < _trending_limit OR (hp.sc_trend = _trending_limit AND hp.id < _post_id))
          WHEN 'hot' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_hot < _hot_limit OR (hp.sc_hot = _hot_limit AND hp.id < _post_id))
          WHEN 'created' THEN (_post_id = 0 OR hp.id < _post_id)
          WHEN 'payout' THEN NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'payout_comments' THEN hp.depth > 0 AND NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'muted' THEN hp.is_grayed AND NOT hp.is_paidout AND hp.payout > 0
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          ELSE True
        END
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
    ) hp
    JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
    JOIN hivemind_app.hive_posts_data hpd ON hpd.id = hp.id
  );

  RETURN _result;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_community;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_community(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _tag TEXT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_hot_limit FLOAT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_community_id INT;
_result JSONB;
BEGIN
  -- Get community id
  SELECT id INTO _community_id FROM hivemind_app.hive_communities WHERE name = _tag LIMIT 1;

  IF _community_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- Get pagination limits based on sort type
  IF _post_id <> 0 THEN
    SELECT sc_trend, sc_hot, payout INTO _trending_limit, _hot_limit, _payout_limit
    FROM hivemind_app.hive_posts WHERE id = _post_id;
  END IF;

  _result = (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'post_id', hp.id,
        'author', ha.name,
        'permlink', hpd.permlink,
        'reblogged', EXISTS (SELECT 1 FROM hivemind_app.hive_reblogs WHERE blogger_id = _observer_id AND post_id = hp.id)
      )
    ), '[]'::jsonb)
    FROM (
      SELECT hp.id, hp.author_id
      FROM hivemind_app.live_posts_view hp
      WHERE
        hp.community_id = _community_id
        AND CASE _sort_type
          WHEN 'trending' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_trend < _trending_limit OR (hp.sc_trend = _trending_limit AND hp.id < _post_id))
          WHEN 'hot' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_hot < _hot_limit OR (hp.sc_hot = _hot_limit AND hp.id < _post_id))
          WHEN 'created' THEN (_post_id = 0 OR hp.id < _post_id)
          WHEN 'payout' THEN NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'payout_comments' THEN hp.depth > 0 AND NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'muted' THEN hp.is_grayed AND NOT hp.is_paidout AND hp.payout > 0
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          ELSE True
        END
        AND (_observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
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
    ) hp
    JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
    JOIN hivemind_app.hive_posts_data hpd ON hpd.id = hp.id
  );

  RETURN _result;
END
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_reblogged_posts_for_tag;
CREATE FUNCTION hivemind_postgrest_utilities.get_reblogged_posts_for_tag(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _tag TEXT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type
)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_trending_limit FLOAT;
_hot_limit FLOAT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_tag_id INT;
_result JSONB;
BEGIN
  -- Get tag id
  SELECT id INTO _tag_id FROM hivemind_app.hive_tag_data WHERE tag = _tag LIMIT 1;

  IF _tag_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- Get pagination limits based on sort type
  IF _post_id <> 0 THEN
    SELECT sc_trend, sc_hot, payout INTO _trending_limit, _hot_limit, _payout_limit
    FROM hivemind_app.hive_posts WHERE id = _post_id;
  END IF;

  _result = (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'post_id', hp.id,
        'author', ha.name,
        'permlink', hpd.permlink,
        'reblogged', EXISTS (SELECT 1 FROM hivemind_app.hive_reblogs WHERE blogger_id = _observer_id AND post_id = hp.id)
      )
    ), '[]'::jsonb)
    FROM (
      SELECT hp.id, hp.author_id
      FROM hivemind_app.live_posts_view hp
      JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id AND hpt.tag_id = _tag_id
      WHERE
        CASE _sort_type
          WHEN 'trending' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_trend < _trending_limit OR (hp.sc_trend = _trending_limit AND hp.id < _post_id))
          WHEN 'hot' THEN NOT hp.is_paidout AND (_post_id = 0 OR hp.sc_hot < _hot_limit OR (hp.sc_hot = _hot_limit AND hp.id < _post_id))
          WHEN 'created' THEN (_post_id = 0 OR hp.id < _post_id)
          WHEN 'payout' THEN NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'payout_comments' THEN hp.depth > 0 AND NOT hp.is_paidout AND hp.payout_at BETWEEN now() + interval '12 hours' AND now() + interval '36 hours'
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          WHEN 'muted' THEN hp.is_grayed AND NOT hp.is_paidout AND hp.payout > 0
            AND (_post_id = 0 OR hp.payout < _payout_limit OR (hp.payout = _payout_limit AND hp.id < _post_id))
          ELSE True
        END
        AND (_observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
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
    ) hp
    JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
    JOIN hivemind_app.hive_posts_data hpd ON hpd.id = hp.id
  );

  RETURN _result;
END
$$
;
