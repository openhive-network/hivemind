DROP FUNCTION IF EXISTS hivemind_app.find_comment_id(character varying, character varying, boolean)
;
CREATE OR REPLACE FUNCTION hivemind_app.find_comment_id(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  __post_id INT = 0;
BEGIN
  IF (_author <> '' OR _permlink <> '') THEN
    SELECT INTO __post_id COALESCE( (
      SELECT hp.id
      FROM hivemind_app.hive_posts hp
      JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
      JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
      WHERE ha.name = _author AND hpd.permlink = _permlink AND hp.counter_deleted = 0
    ), 0 );
    IF _check AND __post_id = 0 THEN
      SELECT INTO __post_id (
        SELECT COUNT(hp.id)
        FROM hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
        WHERE ha.name = _author AND hpd.permlink = _permlink
      );
      IF __post_id = 0 THEN
        RAISE EXCEPTION 'Post %/% does not exist', _author, _permlink USING ERRCODE = 'CEHM2';
      ELSE
        RAISE EXCEPTION 'Post %/% was deleted % time(s)', _author, _permlink, __post_id USING ERRCODE = 'CEHM3';
      END IF;
    END IF;
  END IF;
  RETURN __post_id;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.find_account_id(character varying, boolean)
;
CREATE OR REPLACE FUNCTION hivemind_app.find_account_id(
  in _account hivemind_app.hive_accounts.name%TYPE,
  in _check boolean)
RETURNS INT
LANGUAGE 'plpgsql'
AS
$function$
DECLARE
  __account_id INT = 0;
BEGIN
  IF (_account <> '') THEN
    SELECT INTO __account_id COALESCE( ( SELECT id FROM hivemind_app.hive_accounts WHERE name=_account ), 0 );
    IF _check AND __account_id = 0 THEN
      RAISE EXCEPTION 'Account % does not exist', _account USING ERRCODE = 'CEHM4';
    END IF;
  END IF;
  RETURN __account_id;
END
$function$
;

DROP TYPE IF EXISTS hivemind_app.head_state CASCADE;
CREATE TYPE hivemind_app.head_state AS
(
    num        int,
    created_at timestamp,
    age        int
);

DROP FUNCTION IF EXISTS hivemind_app.get_head_state();
CREATE OR REPLACE FUNCTION hivemind_app.get_head_state()
    RETURNS SETOF hivemind_app.head_state
    LANGUAGE 'plpgsql'
AS
$$
DECLARE
    __num        int;
    __created_at timestamp := '1970-01-01 00:00:00'::timestamp;
    __record     hivemind_app.head_state;
BEGIN
    SELECT current_block_num INTO __num FROM hivemind_app.context_data_view;
    IF __num > 0 THEN
        SELECT created_at INTO __created_at FROM hivemind_app.blocks_view WHERE num = __num;
    ELSE
        -- MIGHT BE NULL
        __num = 0;
    END IF;

    __record.num = __num;
    __record.created_at = __created_at;
    __record.age = extract(epoch from __created_at);

    RETURN NEXT __record;
END
$$
;
