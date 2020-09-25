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
    author_rep FLOAT4,
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
