
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

