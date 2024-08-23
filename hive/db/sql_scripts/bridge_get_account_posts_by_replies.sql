CREATE OR REPLACE FUNCTION hivemind_app.bridge_get_account_posts_by_replies(_account VARCHAR, _author VARCHAR, _permlink VARCHAR, _limit SMALLINT, _observer VARCHAR, _bridge_api BOOLEAN) RETURNS SETOF hivemind_app.bridge_api_post
AS $function$
DECLARE
  __account_id INT;
  __post_id INT;
  __observer_id INT;
BEGIN
  __observer_id = hivemind_app.find_account_id( _observer, True );
  IF NOT _bridge_api AND _permlink <> '' THEN
      -- find blogger account using parent author of page defining post
      __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
      SELECT pp.author_id INTO __account_id
      FROM hivemind_app.hive_posts hp
      JOIN hivemind_app.hive_posts pp ON hp.parent_id = pp.id
      WHERE hp.id = __post_id;
      IF __account_id = 0 THEN __account_id = NULL; END IF;
  ELSE
      __account_id = hivemind_app.find_account_id( _account, True );
      __post_id = hivemind_app.find_comment_id( _author, _permlink, True );
  END IF;
  RETURN QUERY
  WITH replies AS MATERIALIZED --bridge_get_account_posts_by_replies
  (
    SELECT hpr.id
    FROM hivemind_app.live_posts_comments_view hpr
    JOIN hivemind_app.hive_posts hp1 ON hp1.id = hpr.parent_id
    LEFT OUTER JOIN hivemind_app.blacklisted_by_observer_view blacklist ON (__observer_id != 0 AND blacklist.observer_id = __observer_id AND blacklist.blacklisted_id = hp1.author_id)
    WHERE hp1.author_id = __account_id
      AND (__post_id = 0 OR hpr.id < __post_id )
      AND (__observer_id = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = __observer_id AND muted_id = hpr.author_id))
    ORDER BY hpr.id + 1 DESC
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
      NULL
  FROM replies,
  LATERAL hivemind_app.get_post_view_by_id(replies.id) hp
  ORDER BY replies.id DESC
  LIMIT _limit;
END
$function$ LANGUAGE plpgsql STABLE;
