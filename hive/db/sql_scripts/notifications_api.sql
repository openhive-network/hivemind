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
  FROM hive_notifications_view hnv 
  WHERE hnv.dst_id = __account_id AND hnv.created_at > __last_read_at AND hnv.score >= _minimum_score
  ;
END
$BODY$
;

DROP FUNCTION IF EXISTS account_notifications;
CREATE OR REPLACE FUNCTION account_notifications(in _account VARCHAR, in _min_score SMALLINT, in _last_id BIGINT, in _limit SMALLINT)
RETURNS SETOF notification
AS
$function$
DECLARE
  __account_id INT;
BEGIN
  __account_id = find_account_id( _account, True );
  RETURN QUERY SELECT
      hnv.id
    , CAST( hnv.type_id as SMALLINT) as type_id
    , hnv.created_at
    , hnv.src
    , hnv.dst
    , hnv.author
    , hnv.permlink
    , hnv.community
    , hnv.community_title
    , hnv.payload
    , CAST( hnv.score as SMALLINT) as score
  FROM
      hive_notifications_view hnv
  WHERE hnv.dst_id = __account_id AND hnv.score >= _min_score AND ( _last_id = 0 OR hnv.id < _last_id )
  ORDER BY hnv.id DESC
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE
;

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
    , hnv.src
    , hnv.dst
    , hnv.author
    , hnv.permlink
    , hnv.community
    , hnv.community_title
    , hnv.payload
    , CAST( hnv.score as SMALLINT) as score
  FROM
      hive_notifications_view hnv
  WHERE
      hnv.post_id = __post_id AND hnv.score >= _min_score
      AND ( _last_id = 0 OR hnv.id < _last_id )
  ORDER BY hnv.id DESC
  LIMIT _limit;
END
$function$
LANGUAGE plpgsql STABLE
