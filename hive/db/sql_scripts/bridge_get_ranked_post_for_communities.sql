DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_pinned_for_community;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_pinned_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR)
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __observer_id INT;
  __post_id INT;
BEGIN
  __observer_id = hivemind_app.find_account_id( _observer, True );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 AND NOT hivemind_app.is_pinned( __post_id ) THEN
    RETURN;
  END IF;
  RETURN QUERY
  WITH pinned AS MATERIALIZED -- bridge_get_ranked_post_pinned_for_community
  (
    SELECT 
      hp.id
    FROM hivemind_app.live_posts_comments_view hp -- is this really supported for comments (maybe pinning is prevented?)?
    JOIN hivemind_app.hive_communities hc ON hc.id = hp.community_id
    WHERE hc.name = _community AND hp.is_pinned
      AND (__post_id = 0 OR hp.id < __post_id)
      AND (__observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp.author_id))
    ORDER BY hp.id DESC
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
      hp.source,
      hp.muted_reasons
  FROM pinned,
  LATERAL hivemind_app.get_full_post_view_by_id(pinned.id, __observer_id) hp
  ORDER BY hp.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_trends_for_community;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_trends_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _bridge_api BOOLEAN, in _observer VARCHAR )
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
  IF __post_id <> 0 AND NOT hivemind_app.is_pinned( __post_id ) THEN
      SELECT hp.sc_trend INTO __trending_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  ELSE
      __post_id = 0;
  END IF;
  RETURN QUERY
  --- Close related to hive_posts_community_id_not_is_paidout_idx
  WITH trends as MATERIALIZED -- bridge_get_ranked_post_by_trends_for_community
  (
    SELECT
      hp1.id,
      hp1.sc_trend as trend
    FROM hivemind_app.live_posts_view hp1
    JOIN hivemind_app.hive_communities hc ON hp1.community_id = hc.id
    WHERE hc.name = _community 
       AND NOT hp1.is_paidout --use "hive_posts_community_id_not_is_paidout_idx" index
       AND ( NOT _bridge_api OR NOT hp1.is_pinned ) -- concatenated with bridge_get_ranked_post_pinned_for_community when called for bridge_api
       AND ( __post_id = 0 OR hp1.sc_trend < __trending_limit OR ( hp1.sc_trend = __trending_limit AND hp1.id < __post_id ) )
       AND ( __observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  FROM trends,
  LATERAL hivemind_app.get_full_post_view_by_id(trends.id, __observer_id) hp
  ORDER BY trends.trend DESC, trends.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_payout_for_community;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_payout_for_community(in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
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
  WITH payout as MATERIALIZED -- bridge_get_ranked_post_by_payout_for_community
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout
    FROM hivemind_app.live_posts_comments_view hp1
      JOIN hivemind_app.hive_communities hc ON hp1.community_id = hc.id
    WHERE hc.name = _community
      AND NOT hp1.is_paidout 
      AND hp1.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours'
      AND ( __post_id = 0 OR ( hp1.payout + hp1.pending_payout ) < __payout_limit OR ( ( hp1.payout + hp1.pending_payout ) = __payout_limit AND hp1.id < __post_id ) )
      AND (__observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_payout_comments_for_community;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_payout_comments_for_community( in _community VARCHAR,  in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
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
      SELECT ( hp.payout + hp.pending_payout ) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  RETURN QUERY
  WITH payout as MATERIALIZED -- bridge_get_ranked_post_by_payout_comments_for_community
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout
    FROM hivemind_app.live_comments_view hp1
    JOIN hivemind_app.hive_communities hc ON hp1.community_id = hc.id
    WHERE hc.name = _community 
      AND NOT hp1.is_paidout
      AND ( __post_id = 0 OR (hp1.payout + hp1.pending_payout) < __payout_limit
	                  OR ((hp1.payout + hp1.pending_payout) = __payout_limit AND hp1.id < __post_id) )
      AND (__observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_muted_for_community;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_muted_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
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
      SELECT (hp.payout + hp.pending_payout) INTO __payout_limit FROM hivemind_app.hive_posts hp WHERE hp.id = __post_id;
  END IF;
  __observer_id = hivemind_app.find_account_id(_observer, True);
  RETURN QUERY
  WITH payout as MATERIALIZED -- bridge_get_ranked_post_by_muted_for_community
  (
    SELECT
      hp1.id,
      (hp1.payout + hp1.pending_payout) as total_payout
    FROM hivemind_app.live_posts_comments_view hp1
    JOIN hivemind_app.hive_communities hc ON hp1.community_id = hc.id
    JOIN hivemind_app.hive_accounts_view ha ON hp1.author_id = ha.id
    WHERE hc.name = _community
      AND NOT hp1.is_paidout 
      AND ha.is_grayed 
      AND (hp1.payout + hp1.pending_payout) > 0
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

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_hot_for_community;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_hot_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR )
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
  WITH hot AS MATERIALIZED -- bridge_get_ranked_post_by_hot_for_community
  (
    SELECT
      hp1.id,
      hp1.sc_hot AS hot
    FROM hivemind_app.live_posts_view hp1
    JOIN hivemind_app.hive_communities hc ON hp1.community_id = hc.id
    WHERE hc.name = _community 
      AND NOT hp1.is_paidout
      AND ( __post_id = 0 OR hp1.sc_hot < __hot_limit OR (hp1.sc_hot = __hot_limit AND hp1.id < __post_id) )
      AND (__observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
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
  ORDER BY hot.hot DESC, hot.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS hivemind_app.bridge_get_ranked_post_by_created_for_community;
CREATE FUNCTION hivemind_app.bridge_get_ranked_post_by_created_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _bridge_api BOOLEAN, in _observer VARCHAR )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __observer_id INT;
BEGIN
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF __post_id <> 0 AND hivemind_app.is_pinned( __post_id ) THEN
    __post_id = 0;
  END IF;
  RETURN QUERY
  --- Very close related to hive_posts_community_id_not_is_pinned_idx PARTIAL index. Please adjust when any condition will be changed.
  WITH community_data AS MATERIALIZED -- bridge_get_ranked_post_by_created_for_community
  (
    SELECT hc.id
    FROM hivemind_app.hive_communities hc
    WHERE hc.name = _community
  )
 ,base_data AS MATERIALIZED
  (
  SELECT
    hp1.community_id,
    hp1.id,
    hp1.author_id
    FROM hivemind_app.live_posts_view hp1
    WHERE hp1.community_id = (SELECT c.id FROM community_data c)
      AND ( NOT _bridge_api OR NOT hp1.is_pinned ) -- concatenated with bridge_get_ranked_post_pinned_for_community when called for bridge_api
      AND ( __post_id = 0 OR hp1.id < __post_id )
      AND (__observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hp1.author_id))
    ORDER BY hp1.community_id ASC, hp1.id DESC --intentionally added community_id to the `order by` to force using hive_posts_community_id_not_is_pinned_idx
    LIMIT _limit
  ),
  created AS
  (
  SELECT d.id
  FROM base_data d
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
      hp.source,
      hp.muted_reasons
  FROM created,
  LATERAL hivemind_app.get_full_post_view_by_id(created.id, __observer_id) hp
  ORDER BY created.id DESC
  ;
END
$function$
language plpgsql STABLE;
