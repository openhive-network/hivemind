DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_created_for_observer_communities;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_created_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
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
  WITH post_ids AS MATERIALIZED -- bridge_get_ranked_post_by_created_for_observer_communities
  (
    SELECT posts.id
    FROM 
    (
      SELECT community_id
      FROM hivemind_app.hive_subscriptions
      WHERE account_id = __observer_id
    ) communities
    CROSS JOIN LATERAL 
    (
      SELECT hp.id
      FROM hivemind_app.live_posts_view hp
      JOIN hivemind_app.hive_accounts_view har ON (hp.author_id = har.id) 
      WHERE hp.community_id = communities.community_id
        AND NOT har.is_grayed
        AND (__post_id = 0 OR hp.id < __post_id)
        AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
      ORDER BY id DESC
      LIMIT _limit
    ) posts
    ORDER BY posts.id DESC
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
    hp.source,
    hp.muted_reasons
  FROM post_ids,
  LATERAL hivemind_app.get_full_post_view_by_id(post_ids.id, __observer_id) hp
  ORDER BY post_ids.id DESC;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_hot_for_observer_communities;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_hot_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __hot_limit FLOAT;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT hp.sc_hot INTO __hot_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __observer_id = hivemind_app.find_account_id( _observer, True );
  RETURN QUERY 
  WITH hot AS MATERIALIZED -- bridge_get_ranked_post_by_hot_for_observer_communities
  (
    SELECT 
      hp.id
    FROM hivemind_app.live_posts_view hp
    JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
    WHERE hs.account_id = __observer_id 
      AND NOT hp.is_paidout
      AND ( __post_id = 0 OR hp.sc_hot < __hot_limit OR ( hp.sc_hot = __hot_limit AND hp.id < __post_id ) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
    ORDER BY hp.sc_hot DESC, hp.id DESC
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
      hp.source,
      hp.muted_reasons
  FROM hot,
  LATERAL hivemind_app.get_full_post_view_by_id(hot.id, __observer_id) hp
  ORDER BY hp.sc_hot DESC, hp.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_payout_comments_for_observer_communities;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_payout_comments_for_observer_communities( in _observer VARCHAR,  in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hivemind_app.hive_posts.payout%TYPE;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __observer_id = hivemind_app.find_account_id( _observer, True );
  RETURN QUERY
  WITH payout AS MATERIALIZED -- bridge_get_ranked_post_by_payout_comments_for_observer_communities
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout
    FROM hivemind_app.live_comments_view hp1
    JOIN hivemind_app.hive_subscriptions hs ON hp1.community_id = hs.community_id
    WHERE hs.account_id = __observer_id
      AND NOT hp1.is_paidout
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
      hp.source,
      hp.muted_reasons
  FROM payout,
  LATERAL hivemind_app.get_full_post_view_by_id(payout.id, __observer_id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_payout_for_observer_communities;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_payout_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
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
  IF __post_id <> 0 THEN
      SELECT (hp.payout + hp.pending_payout) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __observer_id = hivemind_app.find_account_id( _observer, True );
  __head_block_time = hivemind_app.head_block_time();
  RETURN QUERY 
  WITH payout as MATERIALIZED -- bridge_get_ranked_post_by_payout_for_observer_communities
  (
    SELECT
      hp.id,
      (hp.payout + hp.pending_payout) as total_payout
    FROM hivemind_app.live_posts_comments_view hp
    JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
    WHERE hs.account_id = __observer_id 
      AND NOT hp.is_paidout 
      AND hp.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours'
      AND ( __post_id = 0 OR (hp.payout + hp.pending_payout) < __payout_limit 
	                  OR ((hp.payout + hp.pending_payout) = __payout_limit AND hp.id < __post_id) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
    ORDER BY (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
      hp.source,
      hp.muted_reasons
  FROM payout,
  LATERAL hivemind_app.get_full_post_view_by_id(payout.id, __observer_id) hp
  ORDER BY payout.total_payout DESC, payout.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_promoted_for_observer_communities;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_promoted_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __promoted_limit hivemind_app.hive_posts.promoted%TYPE;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT hp.promoted INTO __promoted_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __observer_id = hivemind_app.find_account_id( _observer, True );
  RETURN QUERY
  WITH promoted AS MATERIALIZED -- bridge_get_ranked_post_by_promoted_for_observer_communities
  (
    SELECT
      hp.id
    FROM hivemind_app.live_posts_view hp
    JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
    WHERE hs.account_id = __observer_id
      AND NOT hp.is_paidout
      AND hp.promoted > 0
      AND ( __post_id = 0 OR hp.promoted < __promoted_limit OR ( hp.promoted = __promoted_limit AND hp.id < __post_id ) )
      AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
    ORDER BY hp.promoted DESC, hp.id DESC
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
      hp.source,
      hp.muted_reasons
  FROM promoted,
  LATERAL hivemind_app.get_full_post_view_by_id(promoted.id, __observer_id) hp
  ORDER BY hp.promoted DESC, hp.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_trends_for_observer_communities;
CREATE OR REPLACE FUNCTION hivemind_app.bridge_get_ranked_post_by_trends_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __observer_id INT;
  __trending_limit FLOAT := 0;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF __post_id <> 0 THEN
      SELECT hp.sc_trend INTO __trending_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __observer_id = hivemind_app.find_account_id( _observer, True );
  RETURN QUERY
  WITH trending AS MATERIALIZED -- bridge_get_ranked_post_by_trends_for_observer_communities
  (
    SELECT
      hp1.id,
      hp1.sc_trend
    FROM hivemind_app.live_posts_view hp1
    JOIN hivemind_app.hive_subscriptions hs ON hp1.community_id = hs.community_id
    WHERE hs.account_id = __observer_id
      AND NOT hp1.is_paidout
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
      hp.source,
      hp.muted_reasons
  FROM trending,
  LATERAL hivemind_app.get_full_post_view_by_id(trending.id, __observer_id) hp
  ORDER BY trending.sc_trend DESC, trending.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_muted_for_observer_communities;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_muted_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __payout_limit hivemind_app.hive_posts.payout%TYPE;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __observer_id = hivemind_app.find_account_id( _observer, True );
  RETURN QUERY 
  WITH muted AS MATERIALIZED -- bridge_get_ranked_post_by_muted_for_observer_communities
  (
    SELECT
      hp.id
      (hp.payout + hp.pending_payout) as total_payout
    FROM hivemind_app.live_posts_comments_view hp
    JOIN hivemind_app.hive_subscriptions hs ON hp.community_id = hs.community_id
    JOIN hivemind_app.hive_accounts_view ha ON ha.id = hp.author_id
    WHERE hs.account_id = __observer_id 
      AND NOT hp.is_paidout 
      AND ha.is_grayed 
      AND ( hp.payout + hp.pending_payout ) > 0
      AND ( __post_id = 0 OR (hp.payout + hp.pending_payout) < __payout_limit 
	                  OR ((hp.payout + hp.pending_payout) = __payout_limit AND hp.id < __post_id) )
    ORDER BY (hp.payout + hp.pending_payout) DESC, hp.id DESC
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
      hp.source,
      hp.muted_reasons
  FROM muted,
  LATERAL hivemind_app.get_full_post_view_by_id(muted.id, __observer_id) hp
  ORDER BY muted.total_payout DESC, hp.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
