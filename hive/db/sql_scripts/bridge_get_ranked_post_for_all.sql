DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_created;
CREATE FUNCTION bridge_get_ranked_post_by_created( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
BEGIN
  IF _author <> '' THEN
      __post_id = find_comment_id( _author, _permlink, True );
  END IF;
  RETURN QUERY SELECT
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
      hp.promoted,
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
      hp.curator_payout_value
  FROM
  (
      SELECT
        hp1.id
      FROM hive_posts hp1 WHERE hp1.depth = 0 AND NOT hp1.is_grayed AND ( __post_id = -1 OR hp1.id < __post_id  )
      ORDER BY hp1.id DESC
      LIMIT _limit
  ) as created
  JOIN hive_posts_view hp ON hp.id = created.id
  ORDER BY created.id DESC LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_hot;
  CREATE FUNCTION bridge_get_ranked_post_by_hot( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __hot_limit FLOAT = -1.0;
  BEGIN
      RAISE NOTICE 'author=%',_author;
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.sc_hot INTO __hot_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      RETURN QUERY SELECT
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
      hp.promoted,
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
      hp.curator_payout_value
  FROM
  (
  SELECT
      hp1.id
    , hp1.sc_hot as hot
  FROM
      hive_posts hp1
  WHERE NOT hp1.is_paidout AND hp1.depth = 0
      AND ( __post_id = -1 OR hp1.sc_hot < __hot_limit OR ( hp1.sc_hot = __hot_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.sc_hot DESC
  LIMIT _limit
  ) as hot
  JOIN hive_posts_view hp ON hp.id = hot.id
  ORDER BY hot.hot DESC, hot.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_muted;
  CREATE FUNCTION bridge_get_ranked_post_by_muted( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __payout_limit hive_posts.payout%TYPE;
    __head_block_time TIMESTAMP;
  BEGIN
      RAISE NOTICE 'author=%',_author;
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
      RETURN QUERY SELECT
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
      hp.promoted,
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
      hp.curator_payout_value
  FROM
  (
  SELECT
      hp1.id
    , hp1.payout as payout
  FROM
      hive_posts hp1
  WHERE NOT hp1.is_paidout AND hp1.is_grayed AND hp1.payout > 0
      AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.payout DESC
  LIMIT _limit
  ) as payout
  JOIN hive_posts_view hp ON hp.id = payout.id
  ORDER BY payout.payout DESC, payout.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_comments;
  CREATE FUNCTION bridge_get_ranked_post_by_payout_comments( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __payout_limit hive_posts.payout%TYPE;
    __head_block_time TIMESTAMP;
  BEGIN
      RAISE NOTICE 'author=%',_author;
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
      RETURN QUERY SELECT
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
      hp.promoted,
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
      hp.curator_payout_value
  FROM
  (
  SELECT
      hp1.id
    , hp1.payout as payout
  FROM
      hive_posts hp1
  WHERE NOT hp1.is_paidout AND hp1.depth > 0
      AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.payout DESC
  LIMIT _limit
  ) as payout
  JOIN hive_posts_view hp ON hp.id = payout.id
  ORDER BY payout.payout DESC, payout.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout;
  CREATE FUNCTION bridge_get_ranked_post_by_payout( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __payout_limit hive_posts.payout%TYPE;
    __head_block_time TIMESTAMP;
  BEGIN
      RAISE NOTICE 'author=%',_author;
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
      RETURN QUERY SELECT
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
      hp.promoted,
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
      hp.curator_payout_value
  FROM
  (
  SELECT
      hp1.id
    , hp1.payout as payout
  FROM
      hive_posts hp1
  WHERE NOT hp1.is_paidout AND hp1.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours'
      AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.payout DESC
  LIMIT _limit
  ) as payout
  JOIN hive_posts_view hp ON hp.id = payout.id
  ORDER BY payout.payout DESC, payout.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_promoted;
  CREATE FUNCTION bridge_get_ranked_post_by_promoted( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __promoted_limit hive_posts.promoted%TYPE = -1.0;
  BEGIN
      RAISE NOTICE 'author=%',_author;
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.promoted INTO __promoted_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      RETURN QUERY SELECT
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
      hp.promoted,
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
      hp.curator_payout_value
  FROM
  (
  SELECT
      hp1.id
    , hp1.promoted as promoted
  FROM
      hive_posts hp1
  WHERE NOT hp1.is_paidout AND hp1.depth > 0 AND hp1.promoted > 0
      AND ( __post_id = -1 OR hp1.promoted < __promoted_limit OR ( hp1.promoted = __promoted_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.promoted DESC
  LIMIT _limit
  ) as promoted
  JOIN hive_posts_view hp ON hp.id = promoted.id
  ORDER BY promoted.promoted DESC, promoted.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;


  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends;
  CREATE FUNCTION bridge_get_ranked_post_by_trends( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __trending_limit FLOAT = -1.0;
  BEGIN
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.sc_trend INTO __trending_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      RETURN QUERY SELECT
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
      hp.promoted,
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
      hp.curator_payout_value
  FROM
  (
  SELECT
      hp1.id
    , hp1.sc_trend as trend
  FROM
      hive_posts hp1
  WHERE NOT hp1.is_paidout AND hp1.depth = 0
      AND ( __post_id = -1 OR hp1.sc_trend < __trending_limit OR ( hp1.sc_trend = __trending_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.sc_trend DESC, hp1.id DESC
  LIMIT _limit
  ) as trends
  JOIN hive_posts_view hp ON hp.id = trends.id
  ORDER BY trends.trend DESC, trends.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;
