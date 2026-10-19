-- Post selection shared by the per-viewer overlay REST endpoints (/blog/reblogs, /blog/votes).
-- They return small per-observer facts for the posts of a ranked feed page, so a front end can
-- cache the anonymous feed and fetch the overlay separately.

DROP TYPE IF EXISTS hivemind_postgrest_utilities.ranked_posts_overlay_request CASCADE;
CREATE TYPE hivemind_postgrest_utilities.ranked_posts_overlay_request AS (
    start_post_id INT,
    observer_id INT,
    page_limit INT,
    tag TEXT,
    sort_type hivemind_postgrest_utilities.ranked_post_sort_type
);

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_ranked_posts_overlay_request;
CREATE FUNCTION hivemind_postgrest_utilities.valid_ranked_posts_overlay_request(
  IN _sort TEXT,
  IN _tag TEXT,
  IN _observer TEXT,
  IN _limit INT,
  IN _start_author TEXT,
  IN _start_permlink TEXT
)
RETURNS hivemind_postgrest_utilities.ranked_posts_overlay_request
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _request hivemind_postgrest_utilities.ranked_posts_overlay_request;
BEGIN
  IF _observer IS NULL OR _observer = '' THEN
    RAISE EXCEPTION 'observer is required for this endpoint';
  END IF;

  _request.page_limit = GREATEST(LEAST(COALESCE(_limit, 20), hivemind_postgrest_utilities.get_max_posts_per_call_limit()), 1);

  _request.start_post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(_start_author, True),
    hivemind_postgrest_utilities.valid_permlink(_start_permlink, True),
    True);

  _request.tag = hivemind_postgrest_utilities.valid_tag(
    hivemind_postgrest_utilities.valid_tag(_tag, True),
    True);

  _request.observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_observer, False),
    True);

  CASE _sort
    WHEN 'trending' THEN _request.sort_type = 'trending';
    WHEN 'hot' THEN _request.sort_type = 'hot';
    WHEN 'created' THEN _request.sort_type = 'created';
    WHEN 'payout' THEN _request.sort_type = 'payout';
    WHEN 'payout_comments' THEN _request.sort_type = 'payout_comments';
    WHEN 'muted' THEN _request.sort_type = 'muted';
    ELSE RAISE EXCEPTION 'Unsupported sort, valid sorts: trending, hot, created, payout, payout_comments, muted';
  END CASE;

  RETURN _request;
END
$$;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_ranked_posts_overlay_internal;
CREATE FUNCTION hivemind_postgrest_utilities.get_ranked_posts_overlay_internal(
  IN _post_id INT,
  IN _observer_id INT,
  IN _limit INT,
  IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type,
  IN _community_id INT,           -- Filter by specific community (NULL = no filter)
  IN _tag_id INT,                 -- Filter by specific tag (NULL = no filter)
  IN _filter_observer_communities BOOLEAN  -- Filter by observer's subscribed communities
)
RETURNS TABLE(post_id INT, author TEXT, permlink TEXT)
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
      posts.id,
      ha.name::TEXT,
      hpd.permlink::TEXT
    FROM (
      SELECT
        hp.id,
        hp.author_id,
        hp.permlink_id,
        CASE _sort_type
          WHEN 'trending' THEN hp.sc_trend
          WHEN 'hot' THEN hp.sc_hot
          WHEN 'payout' THEN hp.payout
          WHEN 'payout_comments' THEN hp.payout
          WHEN 'muted' THEN hp.payout
          ELSE NULL
        END AS sort_value
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
      ORDER BY sort_value DESC NULLS LAST, hp.id DESC
      LIMIT _limit
    ) posts
    JOIN hivemind_app.hive_accounts ha ON ha.id = posts.author_id
    JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = posts.permlink_id
    ORDER BY posts.sort_value DESC NULLS LAST, posts.id DESC;
END
$$;

-- Returns the posts of one page of the ranked feed the request describes, in feed order.
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_ranked_posts_overlay;
CREATE FUNCTION hivemind_postgrest_utilities.get_ranked_posts_overlay(
  IN _request hivemind_postgrest_utilities.ranked_posts_overlay_request
)
RETURNS TABLE(post_id INT, author TEXT, permlink TEXT)
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _community_id INT;
  _tag_id INT;
BEGIN
  IF _request.tag IS NULL OR _request.tag = '' OR _request.tag = 'all' THEN
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_ranked_posts_overlay_internal(
      _request.start_post_id, _request.observer_id, _request.page_limit, _request.sort_type, NULL, NULL, FALSE);
  ELSIF _request.tag = 'my' THEN
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_ranked_posts_overlay_internal(
      _request.start_post_id, _request.observer_id, _request.page_limit, _request.sort_type, NULL, NULL, TRUE);
  ELSIF hivemind_postgrest_utilities.check_community(_request.tag) THEN
    SELECT id INTO _community_id FROM hivemind_app.hive_communities WHERE name = _request.tag LIMIT 1;
    IF _community_id IS NULL THEN
      RETURN;
    END IF;
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_ranked_posts_overlay_internal(
      _request.start_post_id, _request.observer_id, _request.page_limit, _request.sort_type, _community_id, NULL, FALSE);
  ELSE
    SELECT id INTO _tag_id FROM hivemind_app.hive_tag_data WHERE tag = _request.tag LIMIT 1;
    IF _tag_id IS NULL THEN
      RETURN;
    END IF;
    RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.get_ranked_posts_overlay_internal(
      _request.start_post_id, _request.observer_id, _request.page_limit, _request.sort_type, NULL, _tag_id, FALSE);
  END IF;
END
$$;
