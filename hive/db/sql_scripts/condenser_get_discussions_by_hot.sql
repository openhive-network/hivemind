DROP FUNCTION IF EXISTS condenser_get_discussions_by_hot;

CREATE FUNCTION condenser_get_discussions_by_hot( in _tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __community VARCHAR;
  __tag_id INT;
  __category_id INT;
BEGIN

  __post_id     = find_comment_id( _author, _permlink, True );
  __community   = ( SELECT substring(_tag from '^hive-') );

  __tag_id      = ( SELECT id FROM hive_tag_data WHERE tag = _tag );
  __category_id = ( SELECT id FROM hive_category_data WHERE category = _tag );

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
      hp.curator_payout_value,
      hp.is_muted
    FROM hive_posts_view hp
    INNER JOIN hive_post_tags hpt ON hpt.post_id = hp.id
    WHERE hp.is_paidout = '0' AND ( __tag_id = 0 OR hpt.tag_id = __tag_id ) AND ( __post_id = 0 OR hp.id < __post_id )
          AND ( ( __community IS NULL ) OR ( ( __community IS NOT NULL ) AND ( ( __category_id = 0 OR hp.category_id = __category_id ) AND hp.depth = 0 ) ) )
    ORDER BY hp.sc_hot DESC, hp.id DESC LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS condenser_get_discussions_by_hot_with_empty_tag;

CREATE FUNCTION condenser_get_discussions_by_hot_with_empty_tag( in _tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INT;
  __community VARCHAR;
  __category_id INT;
BEGIN

  __post_id     = find_comment_id( _author, _permlink, True );
  __community   = ( SELECT substring(_tag from '^hive-') );

  __category_id = ( SELECT id FROM hive_category_data WHERE category = _tag );

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
      hp.curator_payout_value,
      hp.is_muted
    FROM hive_posts_view hp
    WHERE hp.is_paidout = '0' AND ( __post_id = 0 OR hp.id < __post_id )
          AND ( ( __community IS NULL ) OR ( ( __community IS NOT NULL ) AND ( ( __category_id = 0 OR hp.category_id = __category_id ) AND hp.depth = 0 ) ) )
    ORDER BY hp.sc_hot DESC, hp.id DESC LIMIT _limit;
END
$function$
language plpgsql STABLE;
