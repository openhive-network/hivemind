DROP FUNCTION IF EXISTS list_votes_by_voter_comment( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.list_votes_by_voter_comment
(
  in _VOTER hive_accounts.name%TYPE,
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE _VOTER_ID INT;
DECLARE _POST_ID INT;
BEGIN

_VOTER_ID = find_account_id( _VOTER, _VOTER != '' );
_POST_ID = find_comment_id( _AUTHOR, _PERMLINK, True );

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
        ( v.voter_id = _VOTER_ID and v.post_id >= _POST_ID )
        OR
        ( v.voter_id > _VOTER_ID )
    ORDER BY
        voter_id,
        post_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS list_votes_by_comment_voter( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.list_votes_by_comment_voter
(
  in _VOTER hive_accounts.name%TYPE,
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE _VOTER_ID INT;
DECLARE _POST_ID INT;
BEGIN

_VOTER_ID = find_account_id( _VOTER, _VOTER != '' );
_POST_ID = find_comment_id( _AUTHOR, _PERMLINK, True );

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
        ( v.post_id = _POST_ID and v.voter_id >= _VOTER_ID )
        OR
        ( v.post_id > _POST_ID )
    ORDER BY
        post_id,
        voter_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS list_comments_by_cashout_time(timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_cashout_time(
  in _cashout_time timestamp,
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __post_id INT;
  BEGIN
    __post_id = find_comment_id(_author,_permlink, True);
    RETURN QUERY
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
        SELECT
            hp1.id
        FROM
            hive_posts hp1
        WHERE
            hp1.counter_deleted = 0
            AND NOT hp1.is_muted
            AND hp1.cashout_time > _cashout_time
            OR hp1.cashout_time = _cashout_time
            AND hp1.id >= __post_id AND hp1.id != 0
        ORDER BY
            hp1.cashout_time ASC,
            hp1.id ASC
        LIMIT
            _limit
    ) ds ON ds.id = hp.id
    ORDER BY
        hp.cashout_time ASC,
        hp.id ASC
    ;
  END
  $function$
  LANGUAGE plpgsql
;

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
            hive_posts hp1
        INNER JOIN hive_accounts ha ON ha.id = hp1.author_id
        INNER JOIN hive_permlink_data hpd ON hpd.id = hp1.permlink_id
        WHERE
            hp1.counter_deleted = 0
            AND NOT hp1.is_muted
            AND ha.name > _author
            OR ha.name = _author
            AND hpd.permlink >= _permlink
            AND hp1.id != 0
        ORDER BY
            ha.name ASC,
            hpd.permlink ASC
        LIMIT
            _limit
    ) ds ON ds.id = hp.id
    ORDER BY
        hp.author ASC,
        hp.permlink ASC
  $function$
;

DROP FUNCTION IF EXISTS list_comments_by_root(character varying, character varying, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_root(
  in _root_author hive_accounts.name%TYPE,
  in _root_permlink hive_permlink_data.permlink%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __root_id INT;
    __post_id INT;
  BEGIN
    __root_id = find_comment_id(_root_author, _root_permlink, True);
    __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
    RETURN QUERY
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
      SELECT
        hp2.id
      FROM
        hive_posts hp2
      WHERE
        hp2.counter_deleted = 0
        AND NOT hp2.is_muted
        AND hp2.root_id = __root_id
        AND hp2.id >= __post_id
      ORDER BY
        hp2.id ASC
      LIMIT _limit
    ) ds on hp.id = ds.id
    ORDER BY
      hp.id
    ;
  END
  $function$
  LANGUAGE plpgsql
;

DROP FUNCTION IF EXISTS list_comments_by_parent(character varying, character varying, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_parent(
  in _parent_author hive_accounts.name%TYPE,
  in _parent_permlink hive_permlink_data.permlink%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
AS $function$
DECLARE
  __post_id INT;
  __parent_id INT;
BEGIN
  __parent_id = find_comment_id(_parent_author, _parent_permlink, True);
  __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
  RETURN QUERY
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
    SELECT hp1.id FROM
      hive_posts hp1
    WHERE
      hp1.counter_deleted = 0
      AND NOT hp1.is_muted
      AND hp1.parent_id = __parent_id
      AND hp1.id >= __post_id
    ORDER BY
      hp1.id ASC
    LIMIT
      _limit
  ) ds ON ds.id = hp.id
  ORDER BY
    hp.id
  ;
END
$function$
LANGUAGE plpgsql
;

DROP FUNCTION IF EXISTS list_comments_by_last_update(character varying, timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_last_update(
  in _parent_author hive_accounts.name%TYPE,
  in _updated_at hive_posts.updated_at%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __post_id INT;
    __parent_author_id INT;
  BEGIN
    __parent_author_id = find_account_id(_parent_author, True);
    __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
    RETURN QUERY
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
        SELECT
          hp1.id
        FROM
          hive_posts hp1
        JOIN
          hive_posts hp2 ON hp1.parent_id = hp2.id
        WHERE
          hp1.counter_deleted = 0
          AND NOT hp1.is_muted
          AND hp2.author_id = __parent_author_id
          AND (
            hp1.updated_at < _updated_at
            OR hp1.updated_at = _updated_at
            AND hp1.id >= __post_id
          )
        ORDER BY
          hp1.updated_at DESC,
          hp1.id ASC
        LIMIT
          _limit
    ) ds ON ds.id = hp.id
    ORDER BY
      hp.updated_at DESC,
      hp.id ASC
    ;
  END
  $function$
  LANGUAGE plpgsql
;

DROP FUNCTION IF EXISTS list_comments_by_author_last_update(character varying, timestamp, character varying, character varying, int)
;
CREATE OR REPLACE FUNCTION list_comments_by_author_last_update(
  in _author hive_accounts.name%TYPE,
  in _updated_at hive_posts.updated_at%TYPE,
  in _start_post_author hive_accounts.name%TYPE,
  in _start_post_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT)
  RETURNS SETOF database_api_post
  AS
  $function$
  DECLARE
    __author_id INT;
    __post_id INT;
  BEGIN
    __author_id = find_account_id(_author, True);
    __post_id = find_comment_id(_start_post_author, _start_post_permlink, True);
    RETURN QUERY
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
      SELECT
        hp1.id
      FROM
        hive_posts hp1
      WHERE
        hp1.counter_deleted = 0
        AND NOT hp1.is_muted
        AND hp1.author_id = __author_id
        AND (
          hp1.updated_at < _updated_at
          OR hp1.updated_at = _updated_at
          AND hp1.id >= __post_id
        )
      ORDER BY
        hp1.updated_at DESC,
        hp1.id ASC
      LIMIT
        _limit
    ) ds ON ds.id = hp.id
    ORDER BY
        hp.updated_at DESC,
        hp.id ASC
    ;
  END
  $function$
  LANGUAGE plpgsql
;

DROP FUNCTION IF EXISTS get_account_post_replies;
CREATE FUNCTION get_account_post_replies( in _account VARCHAR, in start_author VARCHAR, in start_permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF INTEGER
AS
$function$
DECLARE
	__post_id INTEGER = -1;
	__account_id INTEGER;
BEGIN
	IF start_author <> '' THEN
    __post_id = find_comment_id( start_author, start_permlink, True );
  END IF;
  __account_id = find_account_id(_account, False);
  IF __account_id = 0 THEN
    RETURN;
  END IF;
	RETURN QUERY SELECT
	hpr.id as id
	FROM hive_posts hpr
	JOIN hive_posts hp ON hp.id = hpr.parent_id
	WHERE hp.author_id = __account_id AND hp.counter_deleted = 0 AND hpr.counter_deleted = 0 AND ( __post_id = -1 OR hpr.id < __post_id  )
	ORDER BY hpr.id DESC LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE
;

DROP INDEX IF EXISTS payout_stats_view_ix1;
DROP INDEX IF EXISTS payout_stats_view_ix2;

DROP MATERIALIZED VIEW IF EXISTS payout_stats_view;

CREATE MATERIALIZED VIEW payout_stats_view AS
  SELECT
        community_id,
        ha.name as author,
        SUM( payout + pending_payout ) payout,
        COUNT(*) posts,
        NULL authors
    FROM hive_posts
    INNER JOIN hive_accounts ha ON ha.id = hive_posts.author_id
    WHERE is_paidout = '0' and counter_deleted = 0 and hive_posts.id != 0
  GROUP BY community_id, author

  UNION ALL

  SELECT
        community_id,
        NULL author,
        SUM( payout + pending_payout ) payout,
        COUNT(*) posts,
        COUNT(DISTINCT(author_id)) authors
  FROM hive_posts
  WHERE is_paidout = '0' and counter_deleted = 0 and id != 0
  GROUP BY community_id

WITH DATA
;

CREATE UNIQUE INDEX payout_stats_view_ix1 ON payout_stats_view (community_id, author );
CREATE INDEX payout_stats_view_ix2 ON payout_stats_view (community_id, author, payout);

DROP FUNCTION IF EXISTS public.update_hive_posts_children_count(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.update_hive_posts_children_count(in _first_block INTEGER, in _last_block INTEGER)
    RETURNS void
    LANGUAGE 'plpgsql'
    VOLATILE
AS $BODY$
BEGIN
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
END
$BODY$;

CREATE TABLE IF NOT EXISTS hive_mentions
(
  post_id INTEGER NOT NULL,
  account_id INTEGER NOT NULL,

  CONSTRAINT hive_mentions_PK PRIMARY KEY (post_id, account_id),
  CONSTRAINT hive_mentions_post_id_FK FOREIGN KEY (post_id)
    REFERENCES public.hive_posts (id),
  CONSTRAINT hive_mentions_account_id_FK FOREIGN KEY (account_id)
    REFERENCES public.hive_accounts (id)
);

DROP FUNCTION IF EXISTS update_hive_posts_mentions(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION update_hive_posts_mentions(in _first_block INTEGER, in _last_block INTEGER)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  FIRST_BLOCK_TIME TIMESTAMP;
  LAST_BLOCK_TIME TIMESTAMP;
BEGIN

  FIRST_BLOCK_TIME = ( SELECT created_at FROM hive_blocks WHERE num = _first_block );
  LAST_BLOCK_TIME = ( SELECT created_at FROM hive_blocks WHERE num = _last_block );

  IF (LAST_BLOCK_TIME - '90 days'::interval) > FIRST_BLOCK_TIME THEN
    FIRST_BLOCK_TIME = LAST_BLOCK_TIME - '90 days'::interval;
  END IF;

  INSERT INTO hive_mentions( post_id, account_id )
    SELECT DISTINCT T.id_post, ha.id
    FROM
      hive_accounts ha
    INNER JOIN
    (
      SELECT T.id_post, LOWER( ( SELECT trim( T.mention::text, '{""}') ) ) mention, T.author_id
      FROM
      (
        SELECT
          hp.id, REGEXP_MATCHES( hpd.body, '(?:^|[^a-zA-Z0-9_!#$%&*@\\/])(?:@)([a-zA-Z0-9\\.-]{1,16}[a-zA-Z0-9])(?![a-z])', 'g') mention, hp.author_id
        FROM hive_posts hp
          INNER JOIN hive_post_data hpd ON hp.id = hpd.id
        WHERE
        (
          hp.created_at >= FIRST_BLOCK_TIME
        )
      )T( id_post, mention, author_id )
    )T( id_post, mention, author_id ) ON ha.name = T.mention
    WHERE ha.id != T.author_id
  ON CONFLICT DO NOTHING;

END
$function$
;

DROP TYPE IF EXISTS bridge_api_post CASCADE;
CREATE TYPE bridge_api_post AS (
    id INTEGER,
    author VARCHAR,
    parent_author VARCHAR,
    author_rep BIGINT,
    root_title VARCHAR,
    beneficiaries JSON,
    max_accepted_payout VARCHAR,
    percent_hbd INTEGER,
    url TEXT,
    permlink VARCHAR,
    parent_permlink_or_category VARCHAR,
    title VARCHAR,
    body TEXT,
    category VARCHAR,
    depth SMALLINT,
    promoted DECIMAL(10,3),
    payout DECIMAL(10,3),
    pending_payout DECIMAL(10,3),
    payout_at TIMESTAMP,
    is_paidout BOOLEAN,
    children INTEGER,
    votes INTEGER,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    rshares NUMERIC,
    abs_rshares NUMERIC,
    json TEXT,
    is_hidden BOOLEAN,
    is_grayed BOOLEAN,
    total_votes BIGINT,
    sc_trend FLOAT4,
    role_title VARCHAR,
    community_title VARCHAR,
    role_id SMALLINT,
    is_pinned BOOLEAN,
    curator_payout_value VARCHAR
);

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_created;
CREATE FUNCTION bridge_get_ranked_post_by_created( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
BEGIN
  IF _author <> '' THEN
      __post_id = find_comment_id( _author, _permlink, True );
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
    FROM hive_posts hp1 WHERE hp1.depth = 0 AND NOT hp1.is_grayed AND ( __post_id = -1 OR hp1.id < __post_id  )
    ORDER BY hp1.id DESC
    LIMIT _limit
) as created
JOIN hive_posts_view hp ON hp.id = created.id
ORDER BY created.id DESC LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_hot;
CREATE FUNCTION bridge_get_ranked_post_by_hot( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __hot_limit FLOAT = -1.0;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_hot INTO __hot_limit FROM hive_posts hp WHERE hp.id = __post_id;
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
  , hp1.sc_hot as hot
FROM
    hive_posts hp1
WHERE NOT hp1.is_paidout AND hp1.depth = 0
    AND ( __post_id = -1 OR hp1.sc_hot < __hot_limit OR ( hp1.sc_hot = __hot_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.sc_hot DESC
LIMIT _limit
) as hot
JOIN hive_posts_view hp ON hp.id = hot.id
ORDER BY hot.hot DESC, hot.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_muted;
CREATE FUNCTION bridge_get_ranked_post_by_muted( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
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
  , hp1.payout as payout
FROM
    hive_posts hp1
WHERE NOT hp1.is_paidout AND hp1.is_grayed AND hp1.payout > 0
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_comments;
CREATE FUNCTION bridge_get_ranked_post_by_payout_comments( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
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
  , hp1.payout as payout
FROM
    hive_posts hp1
WHERE NOT hp1.is_paidout AND hp1.depth > 0
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout;
CREATE FUNCTION bridge_get_ranked_post_by_payout( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
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
  , hp1.payout as payout
FROM
    hive_posts hp1
WHERE NOT hp1.is_paidout AND hp1.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours'
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

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
language plpgsql STABLE;


DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends;
CREATE FUNCTION bridge_get_ranked_post_by_trends( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __trending_limit FLOAT = -1.0;
BEGIN
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_trend INTO __trending_limit FROM hive_posts hp WHERE hp.id = __post_id;
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
  , hp1.sc_trend as trend
FROM
    hive_posts hp1
WHERE NOT hp1.is_paidout AND hp1.depth = 0
    AND ( __post_id = -1 OR hp1.sc_trend < __trending_limit OR ( hp1.sc_trend = __trending_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.sc_trend DESC, hp1.id DESC
LIMIT _limit
) as trends
JOIN hive_posts_view hp ON hp.id = trends.id
ORDER BY trends.trend DESC, trends.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_pinned_for_community;
CREATE FUNCTION bridge_get_ranked_post_pinned_for_community( in _community VARCHAR )
RETURNS SETOF bridge_api_post
AS
$function$
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
      hp.curator_payout_valuep.pending_payout,
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
  hive_posts_view hp
  JOIN hive_communities hc ON hc.id = hp.community_id
  WHERE hc.name = _community AND hp.is_pinned
ORDER BY hp.id DESC;
$function$
language sql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends_for_community;
CREATE FUNCTION bridge_get_ranked_post_by_trends_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __trending_limit FLOAT = -1.0;
BEGIN
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_trend INTO __trending_limit FROM hive_posts hp WHERE hp.id = __post_id;
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
  , hp1.sc_trend as trend
FROM
  hive_posts hp1
  JOIN hive_communities hc ON hp1.community_id = hc.id
WHERE hc.name = _community AND NOT hp1.is_paidout AND hp1.depth = 0
    AND ( __post_id = -1 OR hp1.sc_trend < __trending_limit OR ( hp1.sc_trend = __trending_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.sc_trend DESC, hp1.id DESC
LIMIT _limit
) as trends
JOIN hive_posts_view hp ON hp.id = trends.id
ORDER BY trends.trend DESC, trends.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_promoted_for_community;
CREATE FUNCTION bridge_get_ranked_post_by_promoted_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
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
  JOIN hive_communities hc ON hp1.community_id = hc.id
WHERE hc.name = _community AND NOT hp1.is_paidout AND hp1.depth > 0 AND hp1.promoted > 0
    AND ( __post_id = -1 OR hp1.promoted < __promoted_limit OR ( hp1.promoted = __promoted_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.promoted DESC
LIMIT _limit
) as promoted
JOIN hive_posts_view hp ON hp.id = promoted.id
ORDER BY promoted.promoted DESC, promoted.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_for_community;
CREATE FUNCTION bridge_get_ranked_post_by_payout_for_community(in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
BEGIN
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
    RAISE NOTICE 'post_id=%',__post_id;
    RAISE NOTICE 'payout_limit=%',__payout_limit;
    RAISE NOTICE 'time=%',__head_block_time;
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
  , hp1.payout as payout
FROM
  hive_posts hp1
  JOIN hive_communities hc ON hp1.community_id = hc.id
WHERE hc.name = _community AND NOT hp1.is_paidout AND hp1.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours'
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC, hp1.id DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id DESC LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_comments_for_community;
CREATE FUNCTION bridge_get_ranked_post_by_payout_comments_for_community( in _community VARCHAR,  in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
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
  , hp1.payout as payout
FROM
  hive_posts hp1
  JOIN hive_communities hc ON hp1.community_id = hc.id
WHERE hc.name = _community AND NOT hp1.is_paidout AND hp1.depth > 0
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC, hp1.id DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id DESC LIMIT _limit;
END
$function$
language plpgsql STABLE;


DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_muted_for_community;
CREATE FUNCTION bridge_get_ranked_post_by_muted_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
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
  , hp1.payout as payout
FROM
  hive_posts hp1
  JOIN hive_communities hc ON hp1.community_id = hc.id
WHERE hc.name = _community AND NOT hp1.is_paidout AND hp1.is_grayed AND hp1.payout > 0
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_hot_for_community;
CREATE FUNCTION bridge_get_ranked_post_by_hot_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __hot_limit FLOAT = -1.0;
BEGIN
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_hot INTO __hot_limit FROM hive_posts hp WHERE hp.id = __post_id;
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
  , hp1.sc_hot as hot
FROM
    hive_posts hp1
    JOIN hive_communities hc ON hp1.community_id = hc.id
WHERE hc.name = _community AND NOT hp1.is_paidout AND hp1.depth = 0
    AND ( __post_id = -1 OR hp1.sc_hot < __hot_limit OR ( hp1.sc_hot = __hot_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.sc_hot DESC, hp1.id DESC
LIMIT _limit
) as hot
JOIN hive_posts_view hp ON hp.id = hot.id
ORDER BY hot.hot DESC, hot.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_created_for_community;
CREATE FUNCTION bridge_get_ranked_post_by_created_for_community( in _community VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
BEGIN
  IF _author <> '' THEN
      __post_id = find_comment_id( _author, _permlink, True );
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
    , hp1.created_at as created_at
    FROM
      hive_posts hp1
      JOIN hive_communities hc ON hp1.community_id = hc.id
    WHERE hc.name = _community AND hp1.depth = 0 AND NOT hp1.is_grayed AND ( __post_id = -1 OR hp1.id < __post_id  )
    ORDER BY hp1.id DESC
    LIMIT _limit
) as created
JOIN hive_posts_view hp ON hp.id = created.id
ORDER BY created.created_at DESC, created.id LIMIT _limit;
END
$function$
language plpgsql STABLE;


DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_created_for_observer_communities;
CREATE FUNCTION bridge_get_ranked_post_by_created_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __enable_sort BOOLEAN;
BEGIN
  SHOW enable_sort INTO __enable_sort;
  IF _author <> '' THEN
      __post_id = find_comment_id( _author, _permlink, True );
  END IF;
  SET enable_sort=false;
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
   hive_posts_view hp
   JOIN hive_subscriptions hs ON hp.community_id = hs.community_id
   JOIN hive_accounts ha ON ha.id = hs.account_id
WHERE ha.name = _observer AND  hp.depth = 0 AND NOT hp.is_grayed AND ( __post_id = -1 OR hp.id < __post_id  )
ORDER BY hp.id DESC LIMIT _limit;
IF __enable_sort THEN
	SET enable_sort=true;
ELSE
	SET enable_sort=false;
END IF;
END
$function$
language plpgsql VOLATILE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_hot_for_observer_communities;
CREATE FUNCTION bridge_get_ranked_post_by_hot_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __hot_limit FLOAT;
  __enable_sort BOOLEAN;
BEGIN
    SHOW enable_sort INTO __enable_sort;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_hot INTO __hot_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SET enable_sort=false;
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
     hive_posts_view hp
     JOIN hive_subscriptions hs ON hp.community_id = hs.community_id
     JOIN hive_accounts ha ON ha.id = hs.account_id
  WHERE ha.name = _observer AND NOT hp.is_paidout AND hp.depth = 0
  AND ( __post_id = -1 OR hp.sc_hot < __hot_limit OR ( hp.sc_hot = __hot_limit AND hp.id < __post_id  ) )
  ORDER BY hp.sc_hot DESC, hp.id DESC
  LIMIT _limit;
  IF __enable_sort THEN
  	SET enable_sort=true;
  ELSE
  	SET enable_sort=false;
  END IF;
END
$function$
language plpgsql VOLATILE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_hot_for_observer_communities;
CREATE FUNCTION bridge_get_ranked_post_by_hot_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __hot_limit FLOAT;
  __enable_sort BOOLEAN;
BEGIN
    SHOW enable_sort INTO __enable_sort;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_hot INTO __hot_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SET enable_sort=false;
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
     hive_posts_view hp
     JOIN hive_subscriptions hs ON hp.community_id = hs.community_id
     JOIN hive_accounts ha ON ha.id = hs.account_id
  WHERE ha.name = _observer AND NOT hp.is_paidout AND hp.depth = 0
  AND ( __post_id = -1 OR hp.sc_hot < __hot_limit OR ( hp.sc_hot = __hot_limit AND hp.id < __post_id  ) )
  ORDER BY hp.sc_hot DESC
  LIMIT _limit;
  IF __enable_sort THEN
  	SET enable_sort=true;
  ELSE
  	SET enable_sort=false;
  END IF;
END
$function$
language plpgsql VOLATILE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_comments_for_observer_communities;
CREATE FUNCTION bridge_get_ranked_post_by_payout_comments_for_observer_communities( in _observer VARCHAR,  in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
  __enable_sort BOOLEAN;
BEGIN
    SHOW enable_sort INTO __enable_sort;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
    SET enable_sort=false;
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
	  , hp1.payout as payout
	FROM
	  hive_posts hp1
	  JOIN hive_subscriptions hs ON hp1.community_id = hs.community_id
	  JOIN hive_accounts ha ON ha.id = hs.account_id
	WHERE ha.name = _observer AND NOT hp1.is_paidout AND hp1.depth > 0
     AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
	ORDER BY hp1.payout DESC, hp1.id DESC
	LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id DESC LIMIT _limit;
IF __enable_sort THEN
	SET enable_sort=true;
ELSE
	SET enable_sort=false;
END IF;
END
$function$
language plpgsql VOLATILE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_for_observer_communities;
CREATE FUNCTION bridge_get_ranked_post_by_payout_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
  __enable_sort BOOLEAN;
BEGIN
    SHOW enable_sort INTO __enable_sort;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
    SET enable_sort=false;
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
   hive_posts_view hp
   JOIN hive_subscriptions hs ON hp.community_id = hs.community_id
   JOIN hive_accounts ha ON ha.id = hs.account_id
WHERE ha.name = _observer AND NOT hp.is_paidout AND hp.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours'
AND ( __post_id = -1 OR hp.payout < __payout_limit OR ( hp.payout = __payout_limit AND hp.id < __post_id  ) )
ORDER BY hp.payout DESC, hp.id DESC;
IF __enable_sort THEN
	SET enable_sort=true;
ELSE
	SET enable_sort=false;
END IF;
END
$function$
language plpgsql VOLATILE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_promoted_for_observer_communities;
CREATE FUNCTION bridge_get_ranked_post_by_promoted_for_observer_communities( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __promoted_limit hive_posts.promoted%TYPE;
  __enable_sort BOOLEAN;
BEGIN
    SHOW enable_sort INTO __enable_sort;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.promoted INTO __promoted_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SET enable_sort=false;
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
   hive_posts_view hp
   JOIN hive_subscriptions hs ON hp.community_id = hs.community_id
   JOIN hive_accounts ha ON ha.id = hs.account_id
WHERE ha.name = _observer AND NOT hp.is_paidout AND hp.depth > 0 AND hp.promoted > 0
    AND ( __post_id = -1 OR hp.promoted < __promoted_limit OR ( hp.promoted = __promoted_limit AND hp.id < __post_id  ) )
ORDER BY hp.promoted DESC
LIMIT _limit;
IF __enable_sort THEN
	SET enable_sort=true;
ELSE
	SET enable_sort=false;
END IF;
END
$function$
language plpgsql VOLATILE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends_for_observer_community;
CREATE FUNCTION bridge_get_ranked_post_by_trends_for_observer_community( in _observer VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __trending_limit FLOAT;
  __enable_sort BOOLEAN;
BEGIN
    SHOW enable_sort INTO __enable_sort;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_trend INTO __trending_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SET enable_sort=false;
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
   hive_posts_view hp
   JOIN hive_subscriptions hs ON hp.community_id = hs.community_id
   JOIN hive_accounts ha ON ha.id = hs.account_id
WHERE ha.name = _observer AND NOT hp.is_paidout AND hp.depth = 0
    AND ( __post_id = -1 OR hp.sc_trend < __trending_limit OR ( hp.sc_trend = __trending_limit AND hp.id < __post_id  ) )
ORDER BY hp.sc_trend DESC, hp.id DESC
LIMIT _limit;
IF __enable_sort THEN
	SET enable_sort=true;
ELSE
	SET enable_sort=false;
END IF;
END
$function$
language plpgsql VOLATILE;


DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_created_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_created_for_tag( in tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __hive_tag INTEGER = -1;
BEGIN
  IF _author <> '' THEN
      __post_id = find_comment_id( _author, _permlink, True );
  END IF;
  __hive_tag = find_tag_id( tag, True );
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
      , hp1.created_at as created_at
      FROM
        hive_post_tags hpt
        JOIN hive_posts hp1 ON hp1.id = hpt.post_id
      WHERE hpt.tag_id = __hive_tag AND hp1.depth = 0 AND NOT hp1.is_grayed AND ( __post_id = -1 OR hp1.id < __post_id  )
      ORDER BY hp1.id DESC
      LIMIT _limit
  ) as created
  JOIN hive_posts_view hp ON hp.id = created.id
  ORDER BY created.created_at DESC, created.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_hot_for_tag;
  CREATE FUNCTION bridge_get_ranked_post_by_hot_for_tag( in tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __hot_limit FLOAT = -1.0;
    __hive_tag INTEGER = -1;
  BEGIN
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.sc_hot INTO __hot_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      __hive_tag = find_tag_id( tag, True );
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
    , hp1.sc_hot as hot
  FROM
  	hive_post_tags hpt
    JOIN hive_posts hp1 ON hp1.id = hpt.post_id
  WHERE hpt.tag_id = __hive_tag AND NOT hp1.is_paidout AND hp1.depth = 0
      AND ( __post_id = -1 OR hp1.sc_hot < __hot_limit OR ( hp1.sc_hot = __hot_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.sc_hot DESC, hp1.id DESC
  LIMIT _limit
  ) as hot
  JOIN hive_posts_view hp ON hp.id = hot.id
  ORDER BY hot.hot DESC, hot.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_muted_for_tag;
  CREATE FUNCTION bridge_get_ranked_post_by_muted_for_tag( in tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __payout_limit hive_posts.payout%TYPE;
    __hive_tag INTEGER = -1;
  BEGIN
      RAISE NOTICE 'author=%',_author;
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      __hive_tag = find_tag_id( tag, True );
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
    , hp1.payout as payout
  FROM
    hive_post_tags hpt
    JOIN hive_posts hp1 ON hp1.id = hpt.post_id
  WHERE hpt.tag_id = __hive_tag AND NOT hp1.is_paidout AND hp1.is_grayed AND hp1.payout > 0
      AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
  ORDER BY hp1.payout DESC
  LIMIT _limit
  ) as payout
  JOIN hive_posts_view hp ON hp.id = payout.id
  ORDER BY payout.payout DESC, payout.id LIMIT _limit;
  END
  $function$
  language plpgsql STABLE;

  DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_comments_for_tag;
  CREATE FUNCTION bridge_get_ranked_post_by_payout_comments_for_tag( in tag VARCHAR,  in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
  RETURNS SETOF bridge_api_post
  AS
  $function$
  DECLARE
    __post_id INTEGER = -1;
    __payout_limit hive_posts.payout%TYPE;
    __head_block_time TIMESTAMP;
    __hive_tag INTEGER = -1;
  BEGIN
      RAISE NOTICE 'author=%',_author;
      IF _author <> '' THEN
          __post_id = find_comment_id( _author, _permlink, True );
          SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
      END IF;
      SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
      __hive_tag = find_tag_id( tag, True );
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
  , hp1.payout as payout
FROM
  hive_post_tags hpt
  JOIN hive_posts hp1 ON hp1.id = hpt.post_id
WHERE hpt.tag_id = __hive_tag AND NOT hp1.is_paidout AND hp1.depth > 0
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_payout_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_payout_for_tag( in tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __payout_limit hive_posts.payout%TYPE;
  __head_block_time TIMESTAMP;
  __hive_tag INTEGER = -1;
BEGIN
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.payout INTO __payout_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    SELECT blck.created_at INTO __head_block_time FROM hive_blocks blck ORDER BY blck.num DESC LIMIT 1;
    __hive_tag = find_tag_id( tag, True );
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
  , hp1.payout as payout
FROM
  hive_post_tags hpt
  JOIN hive_posts hp1 ON hp1.id = hpt.post_id
WHERE hpt.tag_id = __hive_tag AND NOT hp1.is_paidout AND hp1.payout_at BETWEEN __head_block_time + interval '12 hours' AND __head_block_time + interval '36 hours'
    AND ( __post_id = -1 OR hp1.payout < __payout_limit OR ( hp1.payout = __payout_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.payout DESC
LIMIT _limit
) as payout
JOIN hive_posts_view hp ON hp.id = payout.id
ORDER BY payout.payout DESC, payout.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_promoted_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_promoted_for_tag( in tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __promoted_limit hive_posts.promoted%TYPE = -1.0;
  __hive_tag INTEGER = -1;
BEGIN
    RAISE NOTICE 'author=%',_author;
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.promoted INTO __promoted_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    __hive_tag = find_tag_id( tag, True );
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
	  hive_post_tags hpt
    JOIN hive_posts hp1 ON hp1.id = hpt.post_id
WHERE hpt.tag_id = __hive_tag AND NOT hp1.is_paidout AND hp1.depth > 0 AND hp1.promoted > 0
    AND ( __post_id = -1 OR hp1.promoted < __promoted_limit OR ( hp1.promoted = __promoted_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.promoted DESC
LIMIT _limit
) as promoted
JOIN hive_posts_view hp ON hp.id = promoted.id
ORDER BY promoted.promoted DESC, promoted.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends_for_tag;
CREATE FUNCTION bridge_get_ranked_post_by_trends_for_tag( in tag VARCHAR, in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __trending_limit FLOAT = -1.0;
  __hive_tag INTEGER = -1;
BEGIN
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_trend INTO __trending_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    __hive_tag = find_tag_id( tag, True );
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
  , hp1.sc_trend as trend
FROM
  hive_post_tags hpt
  JOIN hive_posts hp1 ON hp1.id = hpt.post_id
WHERE hpt.tag_id = __hive_tag AND NOT hp1.is_paidout AND hp1.depth = 0
    AND ( __post_id = -1 OR hp1.sc_trend < __trending_limit OR ( hp1.sc_trend = __trending_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.sc_trend DESC, hp1.id DESC
LIMIT _limit
) as trends
JOIN hive_posts_view hp ON hp.id = trends.id
ORDER BY trends.trend DESC, trends.id LIMIT _limit;
END
$function$
language plpgsql STABLE;

DROP INDEX IF EXISTS hive_posts_sc_trend_id_idx;
CREATE INDEX hive_posts_sc_trend_id_idx ON hive_posts(sc_trend,id);
DROP INDEX IF EXISTS hive_posts_sc_hot_id_idx;
CREATE INDEX hive_posts_sc_hot_id_idx ON hive_posts(sc_hot, id);
DROP INDEX IF EXISTS hive_subscriptions_community_idx;
CREATE INDEX hive_subscriptions_community_idx ON hive_subscriptions(community_id);

--- Account reputation recalc changes:

ALTER TYPE bridge_api_post
  ALTER ATTRIBUTE author_rep SET DATA TYPE BIGINT CASCADE;

CREATE SEQUENCE IF NOT EXISTS public.hive_account_reputation_status_account_id_seq
    INCREMENT 1
    START 1
    MINVALUE 1
    MAXVALUE 2147483647
    CACHE 1;

CREATE TABLE IF NOT EXISTS public.hive_account_reputation_status
(
    account_id INTEGER NOT NULL DEFAULT nextval('hive_account_reputation_status_account_id_seq'::regclass),
    reputation BIGINT NOT NULL,
    is_implicit BOOLEAN NOT NULL,
    CONSTRAINT hive_account_reputation_status_pkey PRIMARY KEY (account_id)
);

ALTER TYPE database_api_vote
  ALTER ATTRIBUTE reputation SET DATA TYPE BIGINT CASCADE;

DROP FUNCTION IF EXISTS list_votes_by_voter_comment( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.list_votes_by_voter_comment
(
  in _VOTER hive_accounts.name%TYPE,
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE __voter_id INT;
DECLARE __post_id INT;
BEGIN

__voter_id = find_account_id( _VOTER, True );
__post_id = find_comment_id( _AUTHOR, _PERMLINK, True );

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
        v.voter_id = __voter_id
        AND v.post_id >= __post_id
    ORDER BY
        v.post_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS list_votes_by_comment_voter( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.list_votes_by_comment_voter
(
  in _VOTER hive_accounts.name%TYPE,
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE __voter_id INT;
DECLARE __post_id INT;
BEGIN

__voter_id = find_account_id( _VOTER, _VOTER != '' ); -- voter is optional
__post_id = find_comment_id( _AUTHOR, _PERMLINK, True );

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
        v.post_id = __post_id
        AND v.voter_id >= __voter_id
    ORDER BY
        v.voter_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS process_reputation_data(in _block_num hive_blocks.num%TYPE, in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE, in _voter hive_accounts.name%TYPE, in _rshares hive_votes.rshares%TYPE)
  ;

DROP TYPE IF EXISTS AccountReputation CASCADE;

CREATE TYPE AccountReputation AS (id int, reputation bigint, is_implicit boolean);

DROP FUNCTION IF EXISTS public.calculate_account_reputations;

CREATE OR REPLACE FUNCTION public.calculate_account_reputations(
  in _first_block_num INTEGER,
  in _last_block_num INTEGER,
  in _tracked_account varchar = null)
    RETURNS SETOF accountreputation
    LANGUAGE 'plpgsql'
    STABLE
AS $BODY$
DECLARE
  __vote_data RECORD;
  __account_reputations AccountReputation[];
  __author_rep bigint;
  __new_author_rep bigint;
  __voter_rep bigint;
  __implicit_voter_rep boolean;
  __implicit_author_rep boolean;
  __rshares bigint;
  __prev_rshares bigint;
  __rep_delta bigint;
  __prev_rep_delta bigint;
  __traced_author int;
  __account_name varchar;
BEGIN
  SELECT INTO __account_reputations ARRAY(SELECT ROW(a.account_id, a.reputation, a.is_implicit)::AccountReputation
  FROM hive_account_reputation_status a
  WHERE a.account_id != 0
  ORDER BY a.account_id);

  SELECT COALESCE((SELECT ha.id FROM hive_accounts ha WHERE ha.name = _tracked_account), 0) INTO __traced_author;

  FOR __vote_data IN
    SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares,
      COALESCE((SELECT prd.rshares
                FROM hive_reputation_data prd
                WHERE prd.author_id = rd.author_id and prd.voter_id = rd.voter_id
                      and prd.permlink = rd.permlink and prd.id < rd.id
                        ORDER BY prd.id DESC LIMIT 1), 0) as prev_rshares
      FROM hive_reputation_data rd
      WHERE (_first_block_num IS NULL AND _last_block_num IS NULL) OR (rd.block_num BETWEEN _first_block_num AND _last_block_num)
      ORDER BY rd.id
    LOOP
      __voter_rep := __account_reputations[__vote_data.voter_id - 1].reputation;
      __implicit_author_rep := __account_reputations[__vote_data.author_id - 1].is_implicit;

      IF __vote_data.author_id = __traced_author THEN
           raise notice 'Processing vote <%> rshares: %, prev_rshares: %', __vote_data.id, __vote_data.rshares, __vote_data.prev_rshares;
       select ha.name into __account_name from hive_accounts ha where ha.id = __vote_data.voter_id;
       raise notice 'Voter `%` (%) reputation: %', __account_name, __vote_data.voter_id,  __voter_rep;
      END IF;

      CONTINUE WHEN __voter_rep < 0;

      __implicit_voter_rep := __account_reputations[__vote_data.voter_id - 1].is_implicit;

      __author_rep := __account_reputations[__vote_data.author_id - 1].reputation;
      __rshares := __vote_data.rshares;
      __prev_rshares := __vote_data.prev_rshares;
      __prev_rep_delta := (__prev_rshares >> 6)::bigint;

      IF NOT __implicit_author_rep AND --- Author must have set explicit reputation to allow its correction
         (__prev_rshares > 0 OR
          --- Voter must have explicitly set reputation to match hived old conditions
         (__prev_rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep - __prev_rep_delta)) THEN
            __author_rep := __author_rep - __prev_rep_delta;
            __implicit_author_rep := __author_rep = 0;
            __account_reputations[__vote_data.author_id - 1] := ROW(__vote_data.author_id, __author_rep, __implicit_author_rep)::AccountReputation;
            IF __vote_data.author_id = __traced_author THEN
             raise notice 'Corrected author_rep by prev_rep_delta: % to have reputation: %', __prev_rep_delta, __author_rep;
            END IF;
      END IF;

      __implicit_voter_rep := __account_reputations[__vote_data.voter_id - 1].is_implicit;
      --- reread voter's rep. since it can change above if author == voter
    __voter_rep := __account_reputations[__vote_data.voter_id - 1].reputation;

      IF __rshares > 0 OR
         (__rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep) THEN

        __rep_delta := (__rshares >> 6)::bigint;
        __new_author_rep = __author_rep + __rep_delta;
        __account_reputations[__vote_data.author_id - 1] := ROW(__vote_data.author_id, __new_author_rep, False)::AccountReputation;
        IF __vote_data.author_id = __traced_author THEN
          raise notice 'Changing account: <%> reputation from % to %', __vote_data.author_id, __author_rep, __new_author_rep;
        END IF;
      ELSE
        IF __vote_data.author_id = __traced_author THEN
            raise notice 'Ignoring reputation change due to unmet conditions... Author_rep: %, Voter_rep: %', __author_rep, __voter_rep;
        END IF;
      END IF;
    END LOOP;

    RETURN QUERY
      SELECT id, Reputation, is_implicit
      FROM unnest(__account_reputations);
END
$BODY$;

DROP FUNCTION IF EXISTS public.update_account_reputations;

CREATE OR REPLACE FUNCTION public.update_account_reputations(
  in _first_block_num INTEGER,
  in _last_block_num INTEGER)
  RETURNS VOID
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
BEGIN
  --- At first step update hive_account_reputation_status table with new accounts.
  INSERT INTO hive_account_reputation_status
    (account_id, reputation, is_implicit)
  SELECT ha.id, 0, True
  FROM hive_accounts ha
  WHERE ha.id != 0
        AND NOT EXISTS (SELECT NULL
                        FROM hive_account_reputation_status rs
                        WHERE rs.account_id = ha.id)
  ;

  UPDATE hive_account_reputation_status urs
  SET reputation = ds.reputation,
      is_implicit = ds.is_implicit
  FROM
  (
    SELECT p.id as account_id, p.reputation, p.is_implicit
    FROM calculate_account_reputations(_first_block_num, _last_block_num) p
  ) ds
  WHERE urs.account_id = ds.account_id
  ;

  UPDATE hive_accounts uha
  SET reputation = rs.reputation
  FROM hive_account_reputation_status rs
  WHERE uha.id = rs.account_id
  ;
END
$BODY$
;

--- cherry-pick-98eaf112

DROP FUNCTION IF EXISTS public.calculate_account_reputations;

CREATE OR REPLACE FUNCTION public.calculate_account_reputations(
  _first_block_num integer,
  _last_block_num integer,
  _tracked_account character varying DEFAULT NULL::character varying)
    RETURNS SETOF accountreputation 
    LANGUAGE 'plpgsql'

    COST 100
    STABLE 
    ROWS 1000
AS $BODY$
DECLARE
  __vote_data RECORD;
  __account_reputations AccountReputation[];
  __author_rep bigint;
  __new_author_rep bigint;
  __voter_rep bigint;
  __implicit_voter_rep boolean;
  __implicit_author_rep boolean;
  __rshares bigint;
  __prev_rshares bigint;
  __rep_delta bigint;
  __prev_rep_delta bigint;
  __traced_author int;
  __account_name varchar;
BEGIN
  SELECT INTO __account_reputations ARRAY(SELECT ROW(a.account_id, a.reputation, a.is_implicit)::AccountReputation
  FROM hive_account_reputation_status a
  WHERE a.account_id != 0
  ORDER BY a.account_id);

  SELECT COALESCE((SELECT ha.id FROM hive_accounts ha WHERE ha.name = _tracked_account), 0) INTO __traced_author;

  FOR __vote_data IN
    SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares,
      COALESCE((SELECT prd.rshares
                FROM hive_reputation_data prd
                WHERE prd.author_id = rd.author_id and prd.voter_id = rd.voter_id
                      and prd.permlink = rd.permlink and prd.id < rd.id
                        ORDER BY prd.id DESC LIMIT 1), 0) as prev_rshares
      FROM hive_reputation_data rd 
      WHERE (_first_block_num IS NULL AND _last_block_num IS NULL) OR (rd.block_num BETWEEN _first_block_num AND _last_block_num)
      ORDER BY rd.id
    LOOP
      __voter_rep := __account_reputations[__vote_data.voter_id - 1].reputation;
      __implicit_author_rep := __account_reputations[__vote_data.author_id - 1].is_implicit;
    
      IF __vote_data.author_id = __traced_author THEN
           raise notice 'Processing vote <%> rshares: %, prev_rshares: %', __vote_data.id, __vote_data.rshares, __vote_data.prev_rshares;
       select ha.name into __account_name from hive_accounts ha where ha.id = __vote_data.voter_id;
       raise notice 'Voter `%` (%) reputation: %', __account_name, __vote_data.voter_id,  __voter_rep;
      END IF;

      CONTINUE WHEN __voter_rep < 0;

      __implicit_voter_rep := __account_reputations[__vote_data.voter_id - 1].is_implicit;
    
      __author_rep := __account_reputations[__vote_data.author_id - 1].reputation;
      __rshares := __vote_data.rshares;
      __prev_rshares := __vote_data.prev_rshares;
      __prev_rep_delta := (__prev_rshares >> 6)::bigint;

      IF NOT __implicit_author_rep AND --- Author must have set explicit reputation to allow its correction
         (__prev_rshares > 0 OR
          --- Voter must have explicitly set reputation to match hived old conditions
         (__prev_rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep - __prev_rep_delta)) THEN
            __author_rep := __author_rep - __prev_rep_delta;
            __implicit_author_rep := __author_rep = 0;
            __account_reputations[__vote_data.author_id - 1] := ROW(__vote_data.author_id, __author_rep, __implicit_author_rep)::AccountReputation;
            IF __vote_data.author_id = __traced_author THEN
             raise notice 'Corrected author_rep by prev_rep_delta: % to have reputation: %', __prev_rep_delta, __author_rep;
            END IF;
      END IF;

      __implicit_voter_rep := __account_reputations[__vote_data.voter_id - 1].is_implicit;
      --- reread voter's rep. since it can change above if author == voter
    __voter_rep := __account_reputations[__vote_data.voter_id - 1].reputation;
    
      IF __rshares > 0 OR
         (__rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep) THEN

        __rep_delta := (__rshares >> 6)::bigint;
        __new_author_rep = __author_rep + __rep_delta;
        __account_reputations[__vote_data.author_id - 1] := ROW(__vote_data.author_id, __new_author_rep, False)::AccountReputation;
        IF __vote_data.author_id = __traced_author THEN
          raise notice 'Changing account: <%> reputation from % to %', __vote_data.author_id, __author_rep, __new_author_rep;
        END IF;
      ELSE
        IF __vote_data.author_id = __traced_author THEN
            raise notice 'Ignoring reputation change due to unmet conditions... Author_rep: %, Voter_rep: %', __author_rep, __voter_rep;
        END IF;
      END IF;
    END LOOP;

    RETURN QUERY
      SELECT id, Reputation, is_implicit
      FROM unnest(__account_reputations)
    WHERE Reputation IS NOT NULL
    ;
END
$BODY$
;

DROP INDEX IF EXISTS hive_reputation_data_block_num_idx;

CREATE INDEX hive_reputation_data_block_num_idx
    ON public.hive_reputation_data (block_num)
    ;

-- Changes from https://gitlab.syncad.com/hive/hivemind/-/merge_requests/208/diffs

DROP VIEW IF EXISTS public.hive_posts_view;
CREATE OR REPLACE VIEW public.hive_posts_view
AS
SELECT hp.id,
  hp.community_id,
  hp.root_id,
  hp.parent_id,
  ha_a.name AS author,
  hp.active,
  hp.author_rewards,
  hp.author_id,
  hpd_p.permlink,
  hpd.title,
  hpd.body,
  hpd.img_url,
  hpd.preview,
  hcd.category,
  hp.depth,
  hp.promoted,
  hp.payout,
  hp.pending_payout,
  hp.payout_at,
  hp.last_payout_at,
  hp.cashout_time,
  hp.is_paidout,
  hp.children,
  0 AS votes,
  0 AS active_votes,
  hp.created_at,
  hp.updated_at,
    COALESCE(
      (
        SELECT SUM( v.rshares )
        FROM hive_votes v
        WHERE v.post_id = hp.id
        GROUP BY v.post_id
      ), 0
    ) AS rshares,
    COALESCE(
      (
        SELECT SUM( CASE v.rshares >= 0 WHEN True THEN v.rshares ELSE -v.rshares END )
        FROM hive_votes v
        WHERE v.post_id = hp.id AND NOT v.rshares = 0
        GROUP BY v.post_id
      ), 0
    ) AS abs_rshares,
    COALESCE(
      (
        SELECT COUNT( 1 )
        FROM hive_votes v
        WHERE v.post_id = hp.id AND v.is_effective
        GROUP BY v.post_id
      ), 0
    ) AS total_votes,
    COALESCE(
      (
        SELECT SUM( CASE v.rshares > 0 WHEN True THEN 1 ELSE -1 END )
        FROM hive_votes v
        WHERE v.post_id = hp.id AND NOT v.rshares = 0
        GROUP BY v.post_id
      ), 0
    ) AS net_votes,
  hpd.json,
  ha_a.reputation AS author_rep,
  hp.is_hidden,
  hp.is_grayed,
  hp.total_vote_weight,
  ha_pp.name AS parent_author,
  ha_pp.id AS parent_author_id,
    ( CASE hp.depth > 0
      WHEN True THEN hpd_pp.permlink
      ELSE hcd.category
    END ) AS parent_permlink_or_category,
  hp.curator_payout_value,
  ha_rp.name AS root_author,
  hpd_rp.permlink AS root_permlink,
  rcd.category as root_category,
  hp.max_accepted_payout,
  hp.percent_hbd,
    True AS allow_replies,
  hp.allow_votes,
  hp.allow_curation_rewards,
  hp.beneficiaries,
    CONCAT('/', rcd.category, '/@', ha_rp.name, '/', hpd_rp.permlink,
      CASE (rp.id)
        WHEN hp.id THEN ''
        ELSE CONCAT('#@', ha_a.name, '/', hpd_p.permlink)
      END
    ) AS url,
  rpd.title AS root_title,
  hp.sc_trend,
  hp.sc_hot,
  hp.is_pinned,
  hp.is_muted,
  hp.is_nsfw,
  hp.is_valid,
  hr.title AS role_title,
  hr.role_id AS role_id,
  hc.title AS community_title,
  hc.name AS community_name,
  hp.block_num
  FROM hive_posts hp
    JOIN hive_posts pp ON pp.id = hp.parent_id
    JOIN hive_posts rp ON rp.id = hp.root_id
    JOIN hive_accounts ha_a ON ha_a.id = hp.author_id
    JOIN hive_permlink_data hpd_p ON hpd_p.id = hp.permlink_id
    JOIN hive_post_data hpd ON hpd.id = hp.id
    JOIN hive_accounts ha_pp ON ha_pp.id = pp.author_id
    JOIN hive_permlink_data hpd_pp ON hpd_pp.id = pp.permlink_id
    JOIN hive_accounts ha_rp ON ha_rp.id = rp.author_id
    JOIN hive_permlink_data hpd_rp ON hpd_rp.id = rp.permlink_id
    JOIN hive_post_data rpd ON rpd.id = rp.id
    JOIN hive_category_data hcd ON hcd.id = hp.category_id
    JOIN hive_category_data rcd ON rcd.id = rp.category_id
    LEFT JOIN hive_communities hc ON hp.community_id = hc.id
    LEFT JOIN hive_roles hr ON hp.author_id = hr.account_id AND hp.community_id = hr.community_id
  WHERE hp.counter_deleted = 0;


