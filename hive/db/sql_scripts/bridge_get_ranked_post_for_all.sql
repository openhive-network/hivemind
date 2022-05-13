DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_created;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_created( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  RETURN QUERY 
  WITH created AS MATERIALIZED -- bridge_get_ranked_post_by_created
  (
    SELECT
      hp1.id,
      blacklist.source
    FROM hivemind_app.live_posts_view hp1
    JOIN hivemind_app.hive_accounts_view ha ON hp1.author_id = ha.id
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE NOT ha.is_grayed
      AND ( __post_id = 0 OR hp1.id < __post_id )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  LATERAL hivemind_app.get_post_view_by_id(created.id) hp
  ORDER BY created.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_hot;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_hot( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __hot_limit FLOAT;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF __post_id <> 0 THEN
      SELECT hp.sc_hot INTO __hot_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  RETURN QUERY
  WITH hot AS MATERIALIZED -- bridge_get_ranked_post_by_hot
  (
    SELECT
      hp1.id,
      hp1.sc_hot,
      blacklist.source
    FROM hivemind_app.live_posts_view hp1
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE NOT hp1.is_paidout
      AND ( __post_id = 0 OR hp1.sc_hot < __hot_limit OR ( hp1.sc_hot = __hot_limit AND hp1.id < __post_id ) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  LATERAL hivemind_app.get_post_view_by_id(hot.id) hp
  ORDER BY hot.sc_hot DESC, hot.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_muted;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_muted( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hivemind_app.hive_posts.payout%TYPE;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id(_observer, True);
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  RETURN QUERY
  WITH payout AS MATERIALIZED -- bridge_get_ranked_post_by_muted
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout,
      blacklist.source
    FROM hivemind_app.live_posts_comments_view hp1
    JOIN hivemind_app.hive_accounts_view ha ON hp1.author_id = ha.id
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE NOT hp1.is_paidout
      AND ha.is_grayed
      AND (hp1.payout + hp1.pending_payout) > 0
      AND ( __post_id = 0 OR ( hp1.payout + hp1.pending_payout ) < __payout_limit OR ( ( hp1.payout + hp1.pending_payout ) = __payout_limit AND hp1.id < __post_id ) )
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
  LATERAL hivemind_app.get_post_view_by_id(payout.id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_payout_comments;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_payout_comments( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hivemind_app.hive_posts.payout%TYPE;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF __post_id <> 0 THEN
      SELECT (hp.payout + hp.pending_payout) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  RETURN QUERY
  WITH payout AS MATERIALIZED -- bridge_get_ranked_post_by_payout_comments
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout,
      blacklist.source
    FROM hivemind_app.live_comments_view hp1
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE NOT hp1.is_paidout
      AND ( __post_id = 0 OR (hp1.payout + hp1.pending_payout) < __payout_limit
                          OR ((hp1.payout + hp1.pending_payout) = __payout_limit AND hp1.id < __post_id) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  LATERAL hivemind_app.get_post_view_by_id(payout.id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_payout;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_payout( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _bridge_api BOOLEAN, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hivemind_app.hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __head_block_time = hivemind_app.head_block_time();
  RETURN QUERY
  WITH payout AS MATERIALIZED -- bridge_get_ranked_post_by_payout
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout,
      blacklist.source
    FROM hivemind_app.live_posts_comments_view hp1
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE NOT hp1.is_paidout
      AND ( ( NOT _bridge_api AND hp1.depth = 0 ) OR ( _bridge_api AND hp1.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours' ) )
      AND ( __post_id = 0 OR ( hp1.payout + hp1.pending_payout ) < __payout_limit OR ( ( hp1.payout + hp1.pending_payout ) = __payout_limit AND hp1.id < __post_id ) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  LATERAL hivemind_app.get_post_view_by_id(payout.id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_promoted;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_promoted( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __promoted_limit hivemind_app.hive_posts.promoted%TYPE;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF __post_id <> 0 THEN
      SELECT hp.promoted INTO __promoted_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  RETURN QUERY
  WITH promoted AS MATERIALIZED -- bridge_get_ranked_post_by_promoted
  (
    SELECT
      hp1.id,
      hp1.promoted,
      blacklist.source
    FROM hivemind_app.live_posts_comments_view hp1
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE NOT hp1.is_paidout
      AND hp1.promoted > 0
      AND ( __post_id = 0 OR hp1.promoted < __promoted_limit OR ( hp1.promoted = __promoted_limit AND hp1.id < __post_id ) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  LATERAL hivemind_app.get_post_view_by_id(promoted.id) hp
  ORDER BY promoted.promoted DESC, promoted.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_trends;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_trends( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __trending_limit FLOAT;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF __post_id <> 0 THEN
      SELECT hp.sc_trend INTO __trending_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  RETURN QUERY 
  WITH trends AS MATERIALIZED -- bridge_get_ranked_post_by_trends
  (
    SELECT
      hp1.id,
      hp1.sc_trend as trend,
      blacklist.source
    FROM
      hivemind_app.live_posts_view hp1
      LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE NOT hp1.is_paidout
      AND ( __post_id = 0 OR hp1.sc_trend < __trending_limit OR ( hp1.sc_trend = __trending_limit AND hp1.id < __post_id ) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  LATERAL hivemind_app.get_post_view_by_id(trends.id) hp
  ORDER BY trends.trend DESC, trends.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
