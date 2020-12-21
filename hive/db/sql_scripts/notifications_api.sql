DROP TYPE IF EXISTS notification CASCADE
;
CREATE TYPE notification AS
(
  id NUMERIC(40,0)
, type_id SMALLINT
, created_at TIMESTAMP
, src VARCHAR
, dst VARCHAR
, author VARCHAR
, permlink VARCHAR
, community VARCHAR
, community_title VARCHAR
, payload VARCHAR
, score SMALLINT
);

DROP FUNCTION IF EXISTS get_number_of_unread_notifications;
CREATE OR REPLACE FUNCTION get_number_of_unread_notifications(in _account VARCHAR, in _minimum_score SMALLINT)
RETURNS TABLE( lastread_at TIMESTAMP, unread BIGINT )
LANGUAGE 'plpgsql' STABLE
AS
$BODY$
DECLARE
    __account_id INT := 0;
    __last_read_at TIMESTAMP;
    __last_read_at_block hive_blocks.num%TYPE;
    __limit_block hive_blocks.num%TYPE = block_before_head( '90 days' );
BEGIN
  __account_id = find_account_id( _account, True );

  SELECT ha.lastread_at INTO __last_read_at
  FROM hive_accounts ha
  WHERE ha.id = __account_id;

  --- Warning given account can have no last_read_at set, so lets fallback to the block limit to avoid comparison to NULL.
  SELECT COALESCE((SELECT hb.num
                   FROM hive_blocks hb
                   WHERE hb.created_at <= __last_read_at
                   ORDER by hb.created_at desc
                   LIMIT 1), __limit_block)
    INTO __last_read_at_block;

  RETURN QUERY SELECT
    __last_read_at as lastread_at,
    count(1) as unread
  FROM hive_notification_cache hnv
  WHERE hnv.dst = __account_id  AND hnv.block_num > __limit_block AND hnv.block_num > __last_read_at_block AND hnv.score >= _minimum_score
  ;
END
$BODY$
;

DROP FUNCTION IF EXISTS account_notifications;

CREATE OR REPLACE FUNCTION public.account_notifications(
  _account character varying,
  _min_score smallint,
  _last_id NUMERIC(40,0),
  _limit smallint)
    RETURNS SETOF notification
    LANGUAGE 'plpgsql'
    STABLE
AS $BODY$
DECLARE
  __account_id INT;
  __limit_block hive_blocks.num%TYPE = block_before_head( '90 days' );
BEGIN
  __account_id = find_account_id( _account, True );
  RETURN QUERY SELECT
      hnv.id
    , CAST( hnv.type_id as SMALLINT) as type_id
    , hnv.created_at
    , hs.name as src
    , hd.name as dst
    , ha.name as author
    , hpd.permlink
    , hnv.community
    , hnv.community_title
    , hnv.payload
    , CAST( hnv.score as SMALLINT) as score
  FROM
  (
    select nv.id, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.score, nv.community, nv.community_title, nv.payload
      from hive_notification_cache nv
  WHERE nv.dst = __account_id  AND nv.block_num > __limit_block AND nv.score >= _min_score AND ( _last_id = 0::NUMERIC(40,0) OR nv.id < _last_id )
  ORDER BY nv.id DESC
  LIMIT _limit
  ) hnv
  join hive_posts hp on hnv.dst_post_id = hp.id
  join hive_accounts ha on hp.author_id = ha.id
  join hive_accounts hs on hs.id = hnv.src
  join hive_accounts hd on hd.id = hnv.dst
  join hive_permlink_data hpd on hp.permlink_id = hpd.id
  ORDER BY hnv.id DESC
  LIMIT _limit;
END
$BODY$;

DROP FUNCTION IF EXISTS post_notifications
;
CREATE OR REPLACE FUNCTION post_notifications(in _author VARCHAR, in _permlink VARCHAR, in _min_score SMALLINT, in _last_id NUMERIC(40,0), in _limit SMALLINT)
RETURNS SETOF notification
AS
$function$
DECLARE
  __post_id INT;
  __limit_block hive_blocks.num%TYPE = block_before_head( '90 days' );
BEGIN
  __post_id = find_comment_id(_author, _permlink, True);
  RETURN QUERY SELECT
      hnv.id
    , CAST( hnv.type_id as SMALLINT) as type_id
    , hnv.created_at
    , hs.name as src
    , hd.name as dst
    , ha.name as author
    , hpd.permlink
    , hnv.community
    , hnv.community_title
    , hnv.payload
    , CAST( hnv.score as SMALLINT) as score
  FROM
  (
    SELECT nv.id, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.score, nv.community, nv.community_title, nv.payload
    FROM hive_notification_cache nv
    WHERE nv.post_id = __post_id AND nv.block_num > __limit_block AND nv.score >= _min_score AND ( _last_id = 0 OR nv.id < _last_id )
    ORDER BY nv.id DESC
    LIMIT _limit
  ) hnv
  JOIN hive_posts hp ON hnv.dst_post_id = hp.id
  JOIN hive_accounts ha ON hp.author_id = ha.id
  JOIN hive_accounts hs ON hs.id = hnv.src
  JOIN hive_accounts hd ON hd.id = hnv.dst
  JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
  ORDER BY hnv.id DESC
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE
;

DROP FUNCTION IF EXISTS update_notification_cache;
;
CREATE OR REPLACE FUNCTION update_notification_cache(in _first_block_num INT, in _last_block_num INT, in _prune_old BOOLEAN)
RETURNS VOID
AS
$function$
DECLARE
  __limit_block hive_blocks.num%TYPE = block_before_head( '90 days' );
  __posts_to_refresh_votes INTEGER[];
  __accounts_to_refresh INTEGER[];
BEGIN
  SET LOCAL work_mem='4GB';
  IF _first_block_num IS NULL THEN
    TRUNCATE TABLE hive_notification_cache;
  	ALTER SEQUENCE hive_notification_cache_id_seq RESTART WITH 1;
  ELSE
	SELECT ARRAY_AGG( DISTINCT reps.author_id ) INTO __accounts_to_refresh
	FROM
	(
		SELECT hrd.author_id FROM hive_reputation_data hrd WHERE hrd.block_num BETWEEN _first_block_num AND _last_block_num
		UNION
		SELECT hrd1.voter_id FROM hive_reputation_data hrd1 WHERE hrd1.block_num BETWEEN _first_block_num AND _last_block_num
	) as reps;

	RAISE NOTICE 'accounts=%',__accounts_to_refresh;

	SELECT ARRAY_AGG( DISTINCT hv.post_id ) INTO __posts_to_refresh_votes FROM hive_votes hv WHERE hv.block_num BETWEEN _first_block_num AND _last_block_num;

	DELETE FROM hive_notification_cache nc
	WHERE
	   (_prune_old AND nc.block_num <= __limit_block)
	OR (nc.type_id = 17 AND nc.dst_post_id = ANY(__posts_to_refresh_votes) ) -- only votes notifs
	OR (nc.type_id BETWEEN 11 AND 16 AND nc.src = ANY(__accounts_to_refresh) ) --only notificaton which dependends on account score
	;
  END IF;
  --the id: notification id | id from sequence
  --	          64b       |       64b
  INSERT INTO hive_notification_cache
  (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
  SELECT CAST( nv.id * 2^64 as NUMERIC(40,0) ) + nextval('hive_notification_cache_id_seq') , nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id, nv.score, nv.payload, nv.community, nv.community_title
  FROM hive_raw_notifications_view nv
  WHERE (_first_block_num IS NULL OR nv.block_num BETWEEN _first_block_num AND _last_block_num)
  AND nv.block_num > __limit_block
  ORDER BY nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id
  ;

  -- insert vote notifications which were changed their score and value
  INSERT INTO hive_notification_cache
  (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
  SELECT CAST( nv.id * 2^64 as NUMERIC(40,0) ) + nextval('hive_notification_cache_id_seq'), nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id, nv.score, nv.payload, nv.community, nv.community_title
  FROM hive_raw_notifications_view_noas nv
  WHERE
  _first_block_num IS NOT NULL
  AND nv.type_id = 17
  AND nv.score > 0
  AND nv.block_num > __limit_block
  AND  nv.block_num NOT BETWEEN _first_block_num AND _last_block_num
  AND nv.dst_post_id = ANY (__posts_to_refresh_votes)
  ORDER BY nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id
  ;

--   --insert notification which score was changed becuase of src reputations
  INSERT INTO hive_notification_cache
  (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
  SELECT CAST( nv.id * 2^64 as NUMERIC(40,0) ) + nextval('hive_notification_cache_id_seq'), nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id, nv.score, nv.payload, nv.community, nv.community_title
  FROM hive_raw_notifications_as_view nv
  WHERE
  _first_block_num IS NOT NULL
  AND nv.block_num > __limit_block
  AND nv.block_num NOT BETWEEN _first_block_num AND _last_block_num
  AND nv.score > 0
  AND nv.src = ANY(__accounts_to_refresh)
  ORDER BY nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id
  ;

  RESET work_mem;
END
$function$
LANGUAGE plpgsql VOLATILE
;
