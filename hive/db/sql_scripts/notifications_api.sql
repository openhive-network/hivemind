DROP TYPE IF EXISTS notification CASCADE
;
CREATE TYPE notification AS
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
BEGIN
  __account_id = find_account_id( _account, True );

  SELECT ha.lastread_at INTO __last_read_at
  FROM hive_accounts ha
  WHERE ha.id = __account_id;

  RETURN QUERY SELECT
    __last_read_at as lastread_at,
    count(1) as unread
  FROM hive_raw_notifications_view hnv
  WHERE hnv.dst = __account_id  AND hnv.block_num > block_before_head( '90 days' ) AND hnv.created_at > __last_read_at AND hnv.score >= _minimum_score
  ;
END
$BODY$
;

DROP FUNCTION IF EXISTS account_notifications;

CREATE OR REPLACE FUNCTION public.account_notifications(
  _account character varying,
  _min_score smallint,
  _last_id bigint,
  _limit smallint)
    RETURNS SETOF notification
    LANGUAGE 'plpgsql'
    STABLE
AS $BODY$
DECLARE
  __account_id INT;
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
      from hive_raw_notifications_view nv
  WHERE nv.dst = __account_id  AND nv.block_num > block_before_head( '90 days' ) AND nv.score >= _min_score AND ( _last_id = 0 OR nv.id < _last_id )
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
CREATE OR REPLACE FUNCTION post_notifications(in _author VARCHAR, in _permlink VARCHAR, in _min_score SMALLINT, in _last_id BIGINT, in _limit SMALLINT)
RETURNS SETOF notification
AS
$function$
DECLARE
  __post_id INT;
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
    FROM hive_raw_notifications_view nv
    WHERE nv.post_id = __post_id AND nv.block_num > block_before_head( '90 days' ) AND nv.score >= _min_score AND ( _last_id = 0 OR nv.id < _last_id )
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
