DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_created_for_tag;
CREATE OR REPLACE FUNCTION bridge_get_ranked_post_by_created_for_tag( _tag VARCHAR, _author VARCHAR, _permlink VARCHAR, _limit SMALLINT, _observer VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __hive_tag INT[];
  __observer_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  __hive_tag = ARRAY_APPEND( __hive_tag, find_tag_id( _tag, True ));
  __observer_id = find_account_id(_observer, True);
  RETURN QUERY
  WITH created AS MATERIALIZED -- bridge_get_ranked_post_by_created_for_tag
  (
    SELECT
      hp1.id,
      blacklist.source
    FROM live_posts_view hp1
    JOIN hive_accounts_view ha ON hp1.author_id = ha.id
    LEFT OUTER JOIN blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.tags_ids @> __hive_tag
      AND ( __post_id = 0 OR hp1.id < __post_id )
      AND NOT ha.is_grayed AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
    ORDER BY hp1.id DESC
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
      hp.curator_payout_value,
      hp.is_muted,
      created.source
  FROM created,
  LATERAL get_post_view_by_id(created.id) hp
  ORDER BY created.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_hot_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_hot_for_tag( in _tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __hot_limit FLOAT;
  __hive_tag INT[];
  __observer_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT hp.sc_hot INTO __hot_limit FROM hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __hive_tag = ARRAY_APPEND( __hive_tag, find_tag_id( _tag, True ));
  __observer_id = find_account_id(_observer, True);
  RETURN QUERY
  WITH hot AS MATERIALIZED -- bridge_get_ranked_post_by_hot_for_tag
  (
    SELECT
      hp1.id,
      hp1.sc_hot as hot,
      blacklist.source
    FROM live_posts_view hp1
    LEFT OUTER JOIN blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.tags_ids @> __hive_tag
      AND NOT hp1.is_paidout
      AND ( __post_id = 0 OR hp1.sc_hot < __hot_limit OR ( hp1.sc_hot = __hot_limit AND hp1.id < __post_id ) )
      AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
    ORDER BY hp1.sc_hot DESC, hp1.id DESC
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
      hp.curator_payout_value,
      hp.is_muted,
      hot.source
  FROM hot,
  LATERAL get_post_view_by_id(hot.id) hp
  ORDER BY hot.hot DESC, hot.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_muted_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_muted_for_tag( in _tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hive_posts.payout%TYPE;
  __hive_tag INT[];
  __observer_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __hive_tag = ARRAY_APPEND( __hive_tag, find_tag_id( _tag, True ) );
  __observer_id = find_account_id(_observer, True);
  RETURN QUERY
  WITH payout AS MATERIALIZED -- bridge_get_ranked_post_by_muted_for_tag
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout,
      blacklist.source
    FROM live_posts_comments_view hp1
    JOIN hive_accounts_view ha ON hp1.author_id = ha.id
    LEFT OUTER JOIN blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.tags_ids @> __hive_tag 
      AND NOT hp1.is_paidout 
      AND ha.is_grayed AND (hp1.payout + hp1.pending_payout) > 0
      AND ( __post_id = 0 OR (hp1.payout + hp1.pending_payout) < __payout_limit 
                          OR ((hp1.payout + hp1.pending_payout) = __payout_limit AND hp1.id < __post_id) )
    ORDER BY ( hp1.payout + hp1.pending_payout ) DESC, hp1.id DESC
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
      hp.curator_payout_value,
      hp.is_muted,
      payout.source
  FROM payout,
  LATERAL get_post_view_by_id(payout.id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_comments_for_category;
CREATE FUNCTION bridge_get_ranked_post_by_payout_comments_for_category( in _category VARCHAR,  in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hive_posts.payout%TYPE;
  __hive_category INT;
  __observer_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __hive_category = find_category_id( _category, True );
  __observer_id = find_account_id(_observer, True);
  RETURN QUERY
  WITH payout AS MATERIALIZED -- bridge_get_ranked_post_by_payout_comments_for_category
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout,
      blacklist.source
    FROM live_comments_view hp1
    LEFT OUTER JOIN blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.category_id = __hive_category 
      AND NOT hp1.is_paidout
      AND ( __post_id = 0 OR (hp1.payout + hp1.pending_payout) < __payout_limit 
                          OR ((hp1.payout + hp1.pending_payout) = __payout_limit AND hp1.id < __post_id) )
      AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
    ORDER BY (hp1.payout + hp1.pending_payout) DESC, hp1.id DESC
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
      hp.curator_payout_value,
      hp.is_muted,
      payout.source
  FROM payout,
  LATERAL get_post_view_by_id(payout.id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_for_category;
CREATE FUNCTION bridge_get_ranked_post_by_payout_for_category( in _category VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _bridge_api BOOLEAN, in _observer VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
  __hive_category INT;
  __observer_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __hive_category = find_category_id( _category, True );
  __head_block_time = head_block_time();
  __observer_id = find_account_id(_observer, True);
  RETURN QUERY
  WITH payout AS MATERIALIZED -- bridge_get_ranked_post_by_payout_for_category
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout,
      blacklist.source
    FROM live_posts_comments_view hp1
    LEFT OUTER JOIN blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.category_id = __hive_category 
      AND NOT hp1.is_paidout
      AND ( ( NOT _bridge_api AND hp1.depth = 0 ) OR ( _bridge_api AND hp1.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours' ) )
      AND ( __post_id = 0 OR (hp1.payout + hp1.pending_payout) < __payout_limit 
                          OR ((hp1.payout + hp1.pending_payout) = __payout_limit AND hp1.id < __post_id) )
      AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
    ORDER BY (hp1.payout + hp1.pending_payout) DESC, hp1.id DESC
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
      hp.curator_payout_value,
      hp.is_muted,
      payout.source
  FROM payout,
  LATERAL get_post_view_by_id(payout.id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_promoted_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_promoted_for_tag( in _tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __promoted_limit hive_posts.promoted%TYPE;
  __hive_tag INT[];
  __observer_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT hp.promoted INTO __promoted_limit FROM hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __hive_tag = ARRAY_APPEND( __hive_tag,  find_tag_id( _tag, True ) );
  __observer_id = find_account_id(_observer, True);
  RETURN QUERY
  WITH promoted AS MATERIALIZED -- bridge_get_ranked_post_by_promoted_for_tag
  (
    SELECT
      hp1.id,
      hp1.promoted,
      blacklist.source
    FROM live_posts_comments_view hp1 -- maybe should be live_posts_view? no, you can promote replies too (probably no one uses it nowadays anyway)
    LEFT OUTER JOIN blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.tags_ids @> __hive_tag
      AND NOT hp1.is_paidout
      AND hp1.promoted > 0
      AND ( __post_id = 0 OR hp1.promoted < __promoted_limit
                          OR (hp1.promoted = __promoted_limit AND hp1.id < __post_id) )
      AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
    ORDER BY hp1.promoted DESC, hp1.id DESC
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
      hp.curator_payout_value,
      hp.is_muted,
      promoted.source
  FROM promoted,
  LATERAL get_post_view_by_id(promoted.id) hp
  ORDER BY promoted.promoted DESC, promoted.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_trends_for_tag( in _tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __trending_limit FLOAT;
  __hive_tag INT[];
  __observer_id INT;
BEGIN
  __post_id = find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT hp.sc_trend INTO __trending_limit FROM hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __hive_tag = ARRAY_APPEND( __hive_tag, find_tag_id( _tag, True ));
  __observer_id = find_account_id(_observer, True);
  RETURN QUERY
  WITH trends AS MATERIALIZED -- bridge_get_ranked_post_by_trends_for_tag
  (
    SELECT
      hp1.id,
      hp1.sc_trend as trend,
      blacklist.source
    FROM live_posts_view hp1
    LEFT OUTER JOIN blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.tags_ids @> __hive_tag 
      AND NOT hp1.is_paidout
      AND ( __post_id = 0 OR hp1.sc_trend < __trending_limit
                          OR (hp1.sc_trend = __trending_limit AND hp1.id < __post_id) )
      AND (NOT EXISTS (SELECT 1 FROM muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
    ORDER BY hp1.sc_trend DESC, hp1.id DESC
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
      hp.curator_payout_value,
      hp.is_muted,
      trends.source
  FROM trends,
  LATERAL get_post_view_by_id(trends.id) hp
  ORDER BY trends.trend DESC, trends.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
