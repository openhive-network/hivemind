DROP FUNCTION IF EXISTS hivemind_app.bridge_get_account_posts_by_blog;

CREATE OR REPLACE FUNCTION hivemind_app.bridge_get_account_posts_by_blog(
  in _account VARCHAR,
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER,
  in _observer VARCHAR,
  in _bridge_api BOOLEAN
)
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER;
  __account_id INTEGER;
  __created_at TIMESTAMP;
  __observer_id INT;
BEGIN
  __observer_id = hivemind_app.find_account_id( _observer, True );
  __account_id = hivemind_app.find_account_id( _account, True );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  IF __post_id <> 0 THEN
    SELECT hfc.created_at INTO __created_at
    FROM hivemind_app.hive_feed_cache hfc
    WHERE hfc.account_id = __account_id AND hfc.post_id = __post_id;
  END IF;

  RETURN QUERY 
  --- Very tightly coupled to hive_feed_cache_account_id_created_at_post_id_idx
  WITH blog AS MATERIALIZED -- bridge_get_account_posts_by_blog
  (
    SELECT 
      hfc.post_id,
      hfc.created_at,
      hfc.account_id,
      blacklist.source
    FROM hivemind_app.hive_feed_cache hfc
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (__observer_id != 0 AND blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hfc.account_id)
    WHERE hfc.account_id = __account_id
      AND ( __post_id = 0 OR hfc.created_at < __created_at
                          OR (hfc.created_at = __created_at AND hfc.post_id < __post_id) )
      AND ( NOT _bridge_api OR
            NOT EXISTS (SELECT NULL FROM hivemind_app.live_posts_comments_view hp1 --should this just be live_posts_view?
                        WHERE hp1.id = hfc.post_id AND hp1.community_id IS NOT NULL
                        AND NOT EXISTS (SELECT NULL FROM hivemind_app.hive_reblogs hr WHERE hr.blogger_id = __account_id AND hr.post_id = hp1.id)
                       )
          )
    ORDER BY hfc.created_at DESC, hfc.post_id DESC
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
      -- is grayed - if author is muted by observer, make post gray
      CASE
        WHEN hp.is_grayed = FALSE AND __observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = (SELECT id FROM hivemind_app.accounts_view WHERE name = hp.author)) THEN True
        else hp.is_grayed
      END,
      hp.total_votes,
      hp.sc_trend,
      hp.role_title,
      hp.community_title,
      hp.role_id,
      hp.is_pinned,
      hp.curator_payout_value,
      hp.is_muted,
      blog.source
    FROM blog,
    LATERAL hivemind_app.get_post_view_by_id(blog.post_id) hp
    ORDER BY blog.created_at DESC, blog.post_id DESC
    LIMIT _limit;
END
$function$
language plpgsql STABLE;
