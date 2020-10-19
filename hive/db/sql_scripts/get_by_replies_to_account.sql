DROP FUNCTION IF EXISTS get_pids_by_replies_to_account;

CREATE OR REPLACE FUNCTION get_pids_by_replies_to_account(
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS TABLE
(
  id hive_posts.id%TYPE
)
AS
$function$
DECLARE
  _start_id INTEGER := 0;
  _is_start_id BOOLEAN := False;
  _id INTEGER;
  _posts_ids INTEGER[];
BEGIN


  IF _permlink <> '' THEN
    _is_start_id = True;
    SELECT
          (SELECT name FROM hive_accounts ha WHERE ha.id = parent.author_id), child.id
    INTO
          _author, _start_id
    FROM hive_posts child
    JOIN hive_posts parent ON child.parent_id = parent.id
    WHERE child.author_id = (SELECT ha.id FROM hive_accounts ha WHERE ha.name = _author)
    AND child.permlink_id = (SELECT hpd.id FROM hive_permlink_data hpd WHERE hpd.permlink = _permlink);
  END IF;

  _id = ( SELECT ha.id FROM hive_accounts ha WHERE ha.name = _author );

  _posts_ids = ARRAY
  (
    SELECT hp.id
    FROM hive_posts hp
    WHERE hp.author_id = _id AND hp.counter_deleted = 0
    ORDER BY hp.id DESC
    LIMIT 10000
  );

  RETURN QUERY
      SELECT hp.id FROM hive_posts hp
      WHERE hp.parent_id = ANY( _posts_ids )
      AND ( ( _is_start_id = False ) OR ( ( _is_start_id = True ) AND ( hp.id <= _start_id ) ) )
      AND hp.counter_deleted = 0
      ORDER BY hp.id DESC
      LIMIT _limit;
END
$function$
LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS get_by_replies_to_account;

CREATE OR REPLACE FUNCTION get_by_replies_to_account(
  in _author VARCHAR,
  in _permlink VARCHAR,
  in _limit INTEGER
)
RETURNS SETOF bridge_api_post
AS
$function$
BEGIN

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
    FROM hive_posts_view hp
    INNER JOIN get_pids_by_replies_to_account( _author, _permlink, _limit ) as fun
    ON hp.id = fun.id;
END
$function$
language plpgsql STABLE;
