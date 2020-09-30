DROP FUNCTION IF EXISTS bridge_get_account_posts_by_posts;

CREATE FUNCTION bridge_get_account_posts_by_posts( in _ACCOUNT VARCHAR, in _AUTHOR VARCHAR, in _PERMLINK VARCHAR, in _LIMIT SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  _POST_ID INTEGER = -1;
BEGIN

    IF _AUTHOR <> '' AND _PERMLINK <> '' THEN
      _POST_ID = find_comment_id( _author, _permlink, True );
    END IF;

  RETURN QUERY
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
            hp.curator_payout_value
        FROM hive_posts_view hp
        WHERE
          hp.author = _ACCOUNT AND hp.depth = 0 AND ( _POST_ID = -1 OR hp.id < _POST_ID ) ORDER BY hp.id DESC LIMIT _LIMIT;
  END
  $function$
  language plpgsql STABLE;
