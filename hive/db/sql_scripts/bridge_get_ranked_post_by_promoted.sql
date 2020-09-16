DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_promoted;
CREATE FUNCTION bridge_get_ranked_post_by_promoted( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __promoted_limit hive_posts.promoted%TYPE = -1.0;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.promoted INTO __promoted_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
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
    hp.curator_payout_value
FROM
(
SELECT
    hp1.id
  , hp1.promoted as promoted
FROM
    hive_posts hp1
WHERE NOT hp1.is_paidout AND hp1.depth > 0 AND hp1.promoted > 0
    AND ( __post_id = -1 OR hp1.promoted < __promoted_limit OR ( hp1.promoted = __promoted_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.promoted DESC
LIMIT _limit
) as promoted
JOIN hive_posts_view hp ON hp.id = promoted.id
ORDER BY promoted.promoted DESC, promoted.id LIMIT _limit;
END
$function$
language plpgsql STABLE
