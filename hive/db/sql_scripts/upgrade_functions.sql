
DROP FUNCTION IF EXISTS find_comment_id(character varying, character varying, boolean)
;
CREATE OR REPLACE FUNCTION find_comment_id(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  post_id INT = 0;
BEGIN
  IF (_author <> '' OR _permlink <> '') THEN
    SELECT INTO post_id COALESCE( (
      SELECT hp.id
      FROM hive_posts hp
      JOIN hive_accounts ha ON ha.id = hp.author_id
      JOIN hive_permlink_data hpd ON hpd.id = hp.permlink_id
      WHERE ha.name = _author AND hpd.permlink = _permlink AND hp.counter_deleted = 0
    ), 0 );
    IF _check AND post_id = 0 THEN
      RAISE EXCEPTION 'Post %/% does not exist', _author, _permlink;
    END IF;
  END IF;
  RETURN post_id;
END
$function$
;

DROP FUNCTION IF EXISTS find_votes( character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.find_votes
(
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE _POST_ID INT;
BEGIN
_POST_ID = find_comment_id( _AUTHOR, _PERMLINK, True);

RETURN QUERY
(
    SELECT
        v.id,
        v.voter,
        v.author,
        v.permlink,
        v.weight,
        v.rshares,
        v.percent,
        v.last_update,
        v.num_changes,
        v.reputation
    FROM
        hive_votes_view v
    WHERE
        v.post_id = _POST_ID
    ORDER BY
        voter_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS list_comments_by_permlink(character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_permlink(
in _author hive_accounts.name%TYPE,
in _permlink hive_permlink_data.permlink%TYPE,
in _limit INT)
RETURNS SETOF database_api_post
LANGUAGE sql
STABLE
AS
$function$
  SELECT
      hp.id, hp.community_id, hp.author, hp.permlink, hp.title, hp.body,
      hp.category, hp.depth, hp.promoted, hp.payout, hp.last_payout_at, hp.cashout_time, hp.is_paidout,
      hp.children, hp.votes, hp.created_at, hp.updated_at, hp.rshares, hp.json,
      hp.is_hidden, hp.is_grayed, hp.total_votes, hp.net_votes, hp.total_vote_weight,
      hp.parent_author, hp.parent_permlink_or_category, hp.curator_payout_value, hp.root_author, hp.root_permlink,
      hp.max_accepted_payout, hp.percent_hbd, hp.allow_replies, hp.allow_votes,
      hp.allow_curation_rewards, hp.beneficiaries, hp.url, hp.root_title, hp.abs_rshares,
      hp.active, hp.author_rewards
  FROM
      hive_posts_view hp
  INNER JOIN
  (
      SELECT hp1.id
      FROM
          hive_posts_api_helper hp1
      INNER JOIN hive_posts hp2 ON hp2.id = hp1.id
      WHERE
          hp2.counter_deleted = 0 
          AND NOT hp2.is_muted
          AND hp1.author > _author
          OR hp1.author = _author
          AND hp1.permlink >= _permlink
          AND hp1.id != 0
      ORDER BY
          hp1.author ASC,
          hp1.permlink ASC
      LIMIT
          _limit
  ) ds ON ds.id = hp.id
  ORDER BY
      hp.author ASC,
      hp.permlink ASC
$function$
;

DROP FUNCTION IF EXISTS public.update_hive_posts_api_helper(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.update_hive_posts_api_helper(in _first_block_num INTEGER, _last_block_num INTEGER)
  RETURNS void
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
BEGIN
IF _first_block_num IS NULL OR _last_block_num IS NULL THEN
  -- initial creation of table.

  INSERT INTO hive_posts_api_helper
  (id, author, permlink)
  SELECT hp.id, hp.author, hp.permlink
  FROM hive_posts_view hp
  ;
ELSE
  -- Regular incremental update.
  INSERT INTO hive_posts_api_helper
  (id, author, permlink)
  SELECT hp.id, hp.author, hp.permlink
  FROM hive_posts_view hp
  WHERE hp.block_num BETWEEN _first_block_num AND _last_block_num AND
          NOT EXISTS (SELECT NULL FROM hive_posts_api_helper h WHERE h.id = hp.id)
  ;
END IF;

END
$BODY$
;
DROP FUNCTION IF EXISTS public.update_hive_posts_children_count(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.update_hive_posts_children_count(in _first_block INTEGER, in _last_block INTEGER)
    RETURNS void
    LANGUAGE 'plpgsql'
    VOLATILE
AS $BODY$
BEGIN
set local enable_sort=false;
set local work_mem='2GB';

UPDATE hive_posts uhp
SET children = data_source.children_count
FROM
(
  WITH recursive tblChild AS
  (
    SELECT s.queried_parent, s.id
    FROM
    (SELECT h1.Parent_Id AS queried_parent, h1.id
      FROM hive_posts h1
      WHERE h1.depth > 0 AND h1.counter_deleted = 0
            AND h1.block_num BETWEEN _first_block AND _last_block
      ORDER BY h1.depth DESC
    ) s
    UNION ALL
    SELECT tblChild.queried_parent, p.id FROM hive_posts p
    JOIN tblChild  ON p.Parent_Id = tblChild.Id
    WHERE p.counter_deleted = 0
  )
  SELECT queried_parent, cast(count(1) AS int) AS children_count
  FROM tblChild
  GROUP BY queried_parent
) data_source
WHERE uhp.id = data_source.queried_parent
;

reset enable_sort;
reset work_mem;

END
$BODY$
;

DROP FUNCTION IF EXISTS get_discussion
;
CREATE OR REPLACE FUNCTION get_discussion(
    in _author hive_accounts.name%TYPE,
    in _permlink hive_permlink_data.permlink%TYPE
)
RETURNS TABLE
(
    id hive_posts.id%TYPE, parent_id hive_posts.parent_id%TYPE, author hive_accounts.name%TYPE, permlink hive_permlink_data.permlink%TYPE,
    title hive_post_data.title%TYPE, body hive_post_data.body%TYPE, category hive_category_data.category%TYPE, depth hive_posts.depth%TYPE,
    promoted hive_posts.promoted%TYPE, payout hive_posts.payout%TYPE, pending_payout hive_posts.pending_payout%TYPE, payout_at hive_posts.payout_at%TYPE,
    is_paidout hive_posts.is_paidout%TYPE, children hive_posts.children%TYPE, created_at hive_posts.created_at%TYPE, updated_at hive_posts.updated_at%TYPE,
    rshares hive_posts_view.rshares%TYPE, abs_rshares hive_posts_view.abs_rshares%TYPE, json hive_post_data.json%TYPE, author_rep hive_accounts.reputation%TYPE,
    is_hidden hive_posts.is_hidden%TYPE, is_grayed BOOLEAN, total_votes BIGINT, sc_trend hive_posts.sc_trend%TYPE,
    acct_author_id hive_posts.author_id%TYPE, root_author hive_accounts.name%TYPE, root_permlink hive_permlink_data.permlink%TYPE,
    parent_author hive_accounts.name%TYPE, parent_permlink_or_category hive_permlink_data.permlink%TYPE, allow_replies BOOLEAN,
    allow_votes hive_posts.allow_votes%TYPE, allow_curation_rewards hive_posts.allow_curation_rewards%TYPE, url TEXT, root_title hive_post_data.title%TYPE,
    beneficiaries hive_posts.beneficiaries%TYPE, max_accepted_payout hive_posts.max_accepted_payout%TYPE, percent_hbd hive_posts.percent_hbd%TYPE,
    curator_payout_value hive_posts.curator_payout_value%TYPE
)
LANGUAGE plpgsql
AS
$function$
DECLARE
    __post_id INT;
BEGIN
    __post_id = find_comment_id( _author, _permlink, True );
    RETURN QUERY
    SELECT
        hpv.id,
        hpv.parent_id,
        hpv.author,
        hpv.permlink,
        hpv.title,
        hpv.body,
        hpv.category,
        hpv.depth,
        hpv.promoted,
        hpv.payout,
        hpv.pending_payout,
        hpv.payout_at,
        hpv.is_paidout,
        hpv.children,
        hpv.created_at,
        hpv.updated_at,
        hpv.rshares,
        hpv.abs_rshares,
        hpv.json,
        hpv.author_rep,
        hpv.is_hidden,
        hpv.is_grayed,
        hpv.total_votes,
        hpv.sc_trend,
        hpv.author_id AS acct_author_id,
        hpv.root_author,
        hpv.root_permlink,
        hpv.parent_author,
        hpv.parent_permlink_or_category,
        hpv.allow_replies,
        hpv.allow_votes,
        hpv.allow_curation_rewards,
        hpv.url,
        hpv.root_title,
        hpv.beneficiaries,
        hpv.max_accepted_payout,
        hpv.percent_hbd,
        hpv.curator_payout_value
    FROM
    (
        WITH RECURSIVE child_posts (id, parent_id) AS
        (
            SELECT hp.id, hp.parent_id
            FROM hive_posts hp
            WHERE hp.id = __post_id
            AND NOT hp.is_muted
            UNION ALL
            SELECT children.id, children.parent_id
            FROM hive_posts children
            JOIN child_posts ON children.parent_id = child_posts.id
            WHERE children.counter_deleted = 0 AND NOT children.is_muted
        )
        SELECT hp2.id
        FROM hive_posts hp2
        JOIN child_posts cp ON cp.id = hp2.id
        ORDER BY hp2.id
    ) ds
    JOIN hive_posts_view hpv ON ds.id = hpv.id
    ORDER BY ds.id
    LIMIT 2000
    ;
END
$function$
;

