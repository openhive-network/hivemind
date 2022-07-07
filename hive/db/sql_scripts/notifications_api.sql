DROP TYPE IF EXISTS hivemind_app.notification CASCADE
;
CREATE TYPE hivemind_app.notification AS
(
  id BIGINT
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
, number_of_mentions INTEGER
);

DROP FUNCTION IF EXISTS hivemind_app.get_number_of_unread_notifications;
CREATE OR REPLACE FUNCTION hivemind_app.get_number_of_unread_notifications(in _account VARCHAR, in _minimum_score SMALLINT)
RETURNS TABLE( lastread_at TIMESTAMP, unread BIGINT )
LANGUAGE 'plpgsql' STABLE
AS
$BODY$
DECLARE
    __account_id INT := 0;
    __last_read_at TIMESTAMP;
    __last_read_at_block hive.hivemind_app_blocks_view.num%TYPE;
    __limit_block hive.hivemind_app_blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
BEGIN
  __account_id = hivemind_app.find_account_id( _account, True );

  SELECT ha.lastread_at INTO __last_read_at
  FROM hivemind_app.hive_accounts ha
  WHERE ha.id = __account_id;

  --- Warning given account can have no last_read_at set, so lets fallback to the block limit to avoid comparison to NULL.
  SELECT COALESCE((SELECT hb.num
                   FROM hive.hivemind_app_blocks_view hb
                   WHERE hb.created_at <= __last_read_at
                   ORDER by hb.created_at desc
                   LIMIT 1), __limit_block)
    INTO __last_read_at_block;

  RETURN QUERY SELECT
    __last_read_at as lastread_at,
    count(1) as unread
  FROM hivemind_app.hive_notification_cache hnv
  WHERE hnv.dst = __account_id  AND hnv.block_num > __limit_block AND hnv.block_num > __last_read_at_block AND hnv.score >= _minimum_score
  ;
END
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.get_number_of_mentions_in_post;
CREATE OR REPLACE FUNCTION hivemind_app.get_number_of_mentions_in_post( _post_id hivemind_app.hive_posts.id%TYPE )
RETURNS INTEGER
LANGUAGE 'plpgsql'
STABLE
AS
$BODY$
DECLARE
    __result INTEGER;
BEGIN
    SELECT COUNT(*) INTO __result FROM hivemind_app.hive_mentions hm WHERE hm.post_id = _post_id;
    return __result;
END
$BODY$;

DROP FUNCTION IF EXISTS hivemind_app.account_notifications;
CREATE OR REPLACE FUNCTION hivemind_app.account_notifications(
  _account character varying,
  _min_score smallint,
  _last_id bigint,
  _limit smallint)
    RETURNS SETOF hivemind_app.notification
    LANGUAGE 'plpgsql'
    STABLE
AS $BODY$
DECLARE
  __account_id INT;
  __limit_block hive.hivemind_app_blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
BEGIN
  __account_id = hivemind_app.find_account_id( _account, True );
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
    , CAST(hnv.score as SMALLINT) as score
    , hm.mentions as number_of_mentions
  FROM
  (
    select nv.id, nv.type_id, nv.created_at, nv.src, nv.dst, nv.post_id, nv.score, nv.community, nv.community_title, nv.payload
      from hivemind_app.hive_notification_cache nv
  WHERE nv.dst = __account_id  AND nv.block_num > __limit_block AND nv.score >= _min_score AND ( _last_id = 0 OR nv.id < _last_id )
  ORDER BY nv.id DESC
  LIMIT _limit
  ) hnv
  join hivemind_app.hive_posts hp on hnv.post_id = hp.id
  join hivemind_app.hive_accounts ha on hp.author_id = ha.id
  join hivemind_app.hive_accounts hs on hs.id = hnv.src
  join hivemind_app.hive_accounts hd on hd.id = hnv.dst
  join hivemind_app.hive_permlink_data hpd on hp.permlink_id = hpd.id,
  lateral ( SELECT
               CASE
                   WHEN hnv.type_id != 16 THEN 0 --evrything else than mentions (only optimization)
                   ELSE hivemind_app.get_number_of_mentions_in_post( hnv.post_id )
               END as mentions
            ) as hm
  ORDER BY hnv.id DESC
  LIMIT _limit;
END
$BODY$;

DROP FUNCTION IF EXISTS hivemind_app.post_notifications
;
CREATE OR REPLACE FUNCTION hivemind_app.post_notifications(in _author VARCHAR, in _permlink VARCHAR, in _min_score SMALLINT, in _last_id BIGINT, in _limit SMALLINT)
RETURNS SETOF hivemind_app.notification
AS
$function$
DECLARE
  __post_id INT;
  __limit_block hive.hivemind_app_blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
BEGIN
  __post_id = hivemind_app.find_comment_id(_author, _permlink, True);
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
    , hm.mentions as number_of_mentions
  FROM
  (
    SELECT nv.id, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.score, nv.community, nv.community_title, nv.payload, nv.post_id
    FROM hivemind_app.hive_notification_cache nv
    WHERE nv.dst_post_id = __post_id AND nv.block_num > __limit_block AND nv.score >= _min_score AND ( _last_id = 0 OR nv.id < _last_id )
    ORDER BY nv.id DESC
    LIMIT _limit
  ) hnv
  JOIN hivemind_app.hive_posts hp ON hnv.post_id = hp.id
  JOIN hivemind_app.hive_accounts ha ON hp.author_id = ha.id
  JOIN hivemind_app.hive_accounts hs ON hs.id = hnv.src
  JOIN hivemind_app.hive_accounts hd ON hd.id = hnv.dst
  JOIN hivemind_app.hive_permlink_data hpd ON hp.permlink_id = hpd.id,
  lateral ( SELECT
               CASE
                   WHEN hnv.type_id != 16 THEN 0 --evrything else than mentions (only optimization)
                   ELSE hivemind_app.get_number_of_mentions_in_post( hnv.post_id )
               END as mentions
            ) as hm
  ORDER BY hnv.id DESC
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE
;

DROP FUNCTION IF EXISTS hivemind_app.update_notification_cache;
;
CREATE OR REPLACE FUNCTION hivemind_app.update_notification_cache(in _first_block_num INT, in _last_block_num INT, in _prune_old BOOLEAN)
RETURNS VOID
AS
$function$
DECLARE
  __limit_block hive.hivemind_app_blocks_view.num%TYPE = hivemind_app.block_before_head( '90 days' );
BEGIN
  IF _first_block_num IS NULL THEN
    TRUNCATE TABLE hivemind_app.hive_notification_cache;
      ALTER SEQUENCE hivemind_app.hive_notification_cache_id_seq RESTART WITH 1;
  ELSE
    DELETE FROM hivemind_app.hive_notification_cache nc WHERE _prune_old AND nc.block_num <= __limit_block;
  END IF;

  INSERT INTO hivemind_app.hive_notification_cache
  (block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
  SELECT nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id, nv.score, nv.payload, nv.community, nv.community_title
  FROM hivemind_app.hive_raw_notifications_view nv
  WHERE nv.block_num > __limit_block AND (_first_block_num IS NULL OR nv.block_num BETWEEN _first_block_num AND _last_block_num)
  ORDER BY nv.block_num, nv.type_id, nv.created_at, nv.src, nv.dst, nv.dst_post_id, nv.post_id
  ;
END
$function$
LANGUAGE plpgsql VOLATILE
;
