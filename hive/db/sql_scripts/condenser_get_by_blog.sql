DROP FUNCTION IF EXISTS hivemind_app.condenser_get_by_blog;

CREATE OR REPLACE FUNCTION hivemind_app.condenser_get_by_blog(
  in _account VARCHAR,
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER := 0;
  __account_id INTEGER := hivemind_app.find_account_id( _account, True );
  __created_at TIMESTAMP;
BEGIN

  IF _permlink <> '' THEN
    __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
    __created_at = 
    (
      SELECT created_at
      FROM hivemind_app.hive_feed_cache
      WHERE account_id = __account_id
      AND post_id = __post_id
    );
  END IF;

  RETURN QUERY 
  WITH blog_posts AS MATERIALIZED -- condenser_get_by_blog
  (
    SELECT hp.id
    FROM hivemind_app.live_posts_comments_view hp
    JOIN hivemind_app.hive_feed_cache hfc ON hp.id = hfc.post_id
    WHERE hfc.account_id = __account_id 
      AND ( ( __post_id = 0 ) OR ( hfc.created_at <= __created_at ) )
    ORDER BY hp.created_at DESC, hp.id DESC
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
      NULL,
      hp.muted_reasons
    FROM blog_posts,
    LATERAL hivemind_app.get_post_view_by_id(blog_posts.id) hp
    ORDER BY hp.created_at DESC, hp.id DESC
    LIMIT _limit;

END
$function$
language plpgsql STABLE;
