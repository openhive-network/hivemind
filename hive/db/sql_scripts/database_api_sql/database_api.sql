-- database_api work in progress, started doing hive_api - list_comments probably soon deprecated due to removal of unused api calls
CREATE OR REPLACE FUNCTION hivemind_helpers.list_comments(
  IN _start TEXT[],
  IN _limit INT,
  IN _order TEXT
)
    RETURNS JSONB
    LANGUAGE plpgsql
    STABLE
AS
$BODY$
DECLARE
  _supported_order_list TEXT[] = ARRAY['by_cashout_time','by_permlink','by_root','by_parent','by_last_update', 'by_author_last_update'];
  __limit INT := hivemind_helpers.valid_limit(_limit,1000,1000);

  _valid_time timestamp without time zone;
  _author TEXT;
  _permlink TEXT;
  _start_post_author TEXT;
  _start_post_permlink TEXT;
BEGIN
IF _order = 'by_cashout_time' THEN
  ASSERT array_length(_start,1) = 3, 'Expecting three arguments in `_start` array: cashout time, optional page _start author and permlink';
  PERFORM hivemind_helpers.valid_date(_start[1]);

  IF SUBSTRING(_start[1] FROM 1 FOR 4) = '1969' THEN
    _valid_time = 'infinity'::timestamp without time zone;
  ELSE
    _valid_time = _start[1]::timestamp without time zone;
  END IF;

  _author = hivemind_helpers.valid_account(_start[2], True);
  _permlink = hivemind_helpers.valid_permlink(_start[3], True);

  RETURN (
    SELECT json_build_object('comments',
      (SELECT (array_agg(row)) FROM (
        SELECT (SELECT * FROM hivemind_helpers.database_post_object((lc.*)::hivemind_app.database_api_post)) FROM hivemind_app.list_comments_by_cashout_time(_valid_time, _author, _permlink, __limit) lc
     ) row)));
ELSIF _order = 'by_permlink' THEN
  ASSERT array_length(_start,1) = 2, 'Expecting two arguments in `start` array: author and permlink';

  _author = _start[1];
  _permlink = _start[2];

  RETURN (
    SELECT json_build_object('comments',
      (SELECT (array_agg(row)) FROM (
        WITH comments AS
        (
          SELECT (lc.*)::hivemind_app.database_api_post AS database_api_post FROM hivemind_app.list_comments_by_permlink(_author, _permlink, __limit) lc
        )
          SELECT hivemind_helpers.database_post_object(database_api_post) FROM comments
     ) row)));
ELSIF _order = 'by_root' THEN
  ASSERT array_length(_start,1) = 4, 'Expecting 4 arguments in `start` array: discussion root author and permlink, optional page _start author and permlink';
  _author = hivemind_helpers.valid_account(_start[1]);
  _permlink = hivemind_helpers.valid_permlink(_start[2]);
  _start_post_author = hivemind_helpers.valid_account(_start[3], True);
  _start_post_permlink = hivemind_helpers.valid_permlink(_start[4], True);
  RETURN (
    SELECT json_build_object('comments',
      (SELECT (array_agg(row)) FROM (
        WITH comments AS
        (
          SELECT (lc.*)::hivemind_app.database_api_post AS database_api_post FROM hivemind_app.list_comments_by_root(_author, _permlink, _start_post_author, _start_post_permlink, __limit) lc
        )
          SELECT * FROM comments c,
          LATERAL hivemind_helpers.database_post_object(c.database_api_post) lc
     ) row)));
ELSIF _order = 'by_parent' THEN
  ASSERT array_length(_start,1) = 4, 'Expecting 4 arguments in `start` array: parent post author and permlink, optional page _start author and permlink';
  _author = hivemind_helpers.valid_account(_start[1]);
  _permlink = hivemind_helpers.valid_permlink(_start[2]);
  _start_post_author = hivemind_helpers.valid_account(_start[3], True);
  _start_post_permlink = hivemind_helpers.valid_permlink(_start[4], True);
  RETURN (
    SELECT json_build_object('comments',
      (SELECT (array_agg(row)) FROM (
        WITH comments AS
        (
          SELECT (lc.*)::hivemind_app.database_api_post AS database_api_post FROM hivemind_app.list_comments_by_parent(_author, _permlink, _start_post_author, _start_post_permlink, __limit) lc
        )
          SELECT * FROM comments c,
          LATERAL hivemind_helpers.database_post_object(c.database_api_post) lc
     ) row)));
ELSIF _order = 'by_last_update' THEN
  ASSERT array_length(_start,1) = 4, 'Expecting 4 arguments in `start` array: parent author, update time, optional page _start author and permlink';
  _author = hivemind_helpers.valid_account(_start[1]);
  PERFORM hivemind_helpers.valid_date(_start[2]);
  _valid_time = _start[2]::timestamp without time zone;
  _start_post_author = hivemind_helpers.valid_account(_start[3], True);
  _start_post_permlink = hivemind_helpers.valid_permlink(_start[4], True);
  RETURN (
    SELECT json_build_object('comments',
      (SELECT (array_agg(row)) FROM (
        WITH comments AS
        (
          SELECT (lc.*)::hivemind_app.database_api_post AS database_api_post FROM hivemind_app.list_comments_by_last_update(_author, _valid_time, _start_post_author, _start_post_permlink, __limit) lc
        )
          SELECT hivemind_helpers.database_post_object(database_api_post) FROM comments
     ) row)));
ELSIF _order = 'by_author_last_update' THEN
  ASSERT array_length(_start,1) = 4, 'Expecting 4 arguments in `start` array: author, update time, optional page _start author and permlink';
  _author = hivemind_helpers.valid_account(_start[1]);
  PERFORM hivemind_helpers.valid_date(_start[2]);
  _valid_time = _start[2]::timestamp without time zone;
  _start_post_author = hivemind_helpers.valid_account(_start[3], True);
  _start_post_permlink = hivemind_helpers.valid_permlink(_start[4], True);
  RETURN (
    SELECT json_build_object('comments',
      (SELECT (array_agg(row)) FROM (
        WITH comments AS
        (
          SELECT (lc.*)::hivemind_app.database_api_post AS database_api_post FROM hivemind_app.list_comments_by_author_last_update(_author, _valid_time, _start_post_author, _start_post_permlink, __limit) lc
        )
          SELECT hivemind_helpers.database_post_object(database_api_post) FROM comments
     ) row)));
ELSE
  RAISE EXCEPTION 'Unsupported order, valid orders: `%`', _supported_order_list;
END IF;

END;
$BODY$
;

/*
  SELECT * FROM comments c,
  LATERAL hivemind_helpers.database_post_object(c.database_api_post) lc

  doesnt help - i cant get rid of object in object 
*/


/*

curl -s --data '{"jsonrpc":"2.0", "method":"database_api.list_comments", "params": {"start":["1970-01-01T00:00:00","",""], "limit":10, "order":"by_cashout_time"}, "id":1}' https://api.hive.blog

curl -s --data '{"jsonrpc":"2.0", "method":"database_api.list_comments", "params": {"start":["",""], "limit":10, "order":"by_permlink"}, "id":1}' https://api.hive.blog

curl -s --data '{"jsonrpc":"2.0", "method":"database_api.list_comments", "params": {"start":["hiveio","announcing-the-launch-of-hive-blockchain","",""], "limit":10, "order":"by_root"}, "id":1}' https://api.hive.blog

curl -s --data '{"jsonrpc":"2.0", "method":"database_api.list_comments", "params": {"start":["hiveio","announcing-the-launch-of-hive-blockchain","",""], "limit":10, "order":"by_parent"}, "id":1}' https://api.hive.blog

curl -s --data '{"jsonrpc":"2.0", "method":"database_api.list_comments", "params": {"start":["hiveio","1970-01-01T00:00:00","",""], "limit":10, "order":"by_last_update"}, "id":1}' https://api.hive.blog

curl -s --data '{"jsonrpc":"2.0", "method":"database_api.list_comments", "params": {"start":["hiveio","1970-01-01T00:00:00","",""], "limit":10, "order":"by_author_last_update"}, "id":1}' https://api.hive.blog

*/
