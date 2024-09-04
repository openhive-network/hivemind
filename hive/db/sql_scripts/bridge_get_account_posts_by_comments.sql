DROP FUNCTION IF EXISTS hivemind_app.bridge_get_account_posts_by_comments;

CREATE FUNCTION hivemind_app.bridge_get_account_posts_by_comments( in _account VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT, in _observer VARCHAR  )
RETURNS SETOF hivemind_app.bridge_api_post
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
  __observer_id INT;
BEGIN
  __account_id = hivemind_app.find_account_id( _account, True );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  __observer_id = hivemind_app.find_account_id( _observer, True );
  RETURN QUERY
  WITH ds AS MATERIALIZED --bridge_get_account_posts_by_comments
  (
    SELECT hp1.id, hp1.author_id, blacklist.source
    FROM hivemind_app.live_comments_view hp1
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (__observer_id != 0 AND blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.author_id = __account_id
      AND (__post_id = 0 OR hp1.id < __post_id)
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
      -- is grayed - if author is muted by observer, make post gray
      CASE
        WHEN hp.is_grayed = FALSE AND __observer_id <> 0 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = ds.author_id) THEN True
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
      ds.source
  FROM ds,
  LATERAL hivemind_app.get_post_view_by_id(ds.id) hp
  ORDER BY ds.id DESC
  LIMIT _limit;
END
$function$
language plpgsql STABLE;
