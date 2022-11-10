DROP FUNCTION IF EXISTS hivemind_app.max_time_stamp() CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.max_time_stamp( _first TIMESTAMP, _second TIMESTAMP )
RETURNS TIMESTAMP
LANGUAGE 'plpgsql'
IMMUTABLE
AS $BODY$
BEGIN
  IF _first > _second THEN
        RETURN _first;
    ELSE
        RETURN _second;
    END IF;
END
$BODY$;

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

DROP FUNCTION IF EXISTS hivemind_app.find_tag_id CASCADE
;
CREATE OR REPLACE FUNCTION hivemind_app.find_tag_id(
    in _tag_name hivemind_app.hive_tag_data.tag%TYPE,
    in _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  __tag_id INT = 0;
BEGIN
  IF (_tag_name <> '') THEN
    SELECT INTO __tag_id COALESCE( ( SELECT id FROM hivemind_app.hive_tag_data WHERE tag=_tag_name ), 0 );
    IF _check AND __tag_id = 0 THEN
      RAISE EXCEPTION 'Tag % does not exist', _tag_name USING ERRCODE = 'CEHM5';
    END IF;
  END IF;
  RETURN __tag_id;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.find_category_id CASCADE
;
CREATE OR REPLACE FUNCTION hivemind_app.find_category_id(
    in _category_name hivemind_app.hive_category_data.category%TYPE,
    in _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  __category_id INT = 0;
BEGIN
  IF (_category_name <> '') THEN
    SELECT INTO __category_id COALESCE( ( SELECT id FROM hivemind_app.hive_category_data WHERE category=_category_name ), 0 );
    IF _check AND __category_id = 0 THEN
      RAISE EXCEPTION 'Category % does not exist', _category_name USING ERRCODE = 'CEHM6';
    END IF;
  END IF;
  RETURN __category_id;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.find_community_id CASCADE
;
CREATE OR REPLACE FUNCTION hivemind_app.find_community_id(
    in _community_name hivemind_app.hive_communities.name%TYPE,
    in _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  __community_id INT = 0;
BEGIN
  IF (_community_name <> '') THEN
    SELECT INTO __community_id COALESCE( ( SELECT id FROM hivemind_app.hive_communities WHERE name=_community_name ), 0 );
    IF _check AND __community_id = 0 THEN
      RAISE EXCEPTION 'Community % does not exist', _community_name USING ERRCODE = 'CEHM7';
    END IF;
  END IF;
  RETURN __community_id;
END
$function$
;

--Maybe better to convert roles to ENUM
DROP FUNCTION IF EXISTS hivemind_app.get_role_name
;
CREATE OR REPLACE FUNCTION hivemind_app.get_role_name(in _role_id INT)
RETURNS VARCHAR
LANGUAGE 'plpgsql'
AS
$function$
BEGIN
    RETURN CASE _role_id
        WHEN -2 THEN 'muted'
        WHEN 0 THEN 'guest'
        WHEN 2 THEN 'member'
        WHEN 4 THEN 'mod'
        WHEN 6 THEN 'admin'
        WHEN 8 THEN 'owner'
    END;
    RAISE EXCEPTION 'role id not found' USING ERRCODE = 'CEHM8';
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.is_pinned
;
CREATE OR REPLACE FUNCTION hivemind_app.is_pinned(in _post_id INT)
RETURNS boolean
LANGUAGE 'plpgsql'
AS
$function$
BEGIN
    RETURN is_pinned FROM hivemind_app.hive_posts WHERE id = _post_id LIMIT 1
    ;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.find_subscription_id CASCADE
;
CREATE OR REPLACE FUNCTION hivemind_app.find_subscription_id(
    in _account hivemind_app.hive_accounts.name%TYPE,
    in _community_name hivemind_app.hive_communities.name%TYPE,
    in _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  __subscription_id INT = 0;
BEGIN
  IF (_account <> '') THEN
    SELECT INTO __subscription_id COALESCE( (
    SELECT hs.id FROM hivemind_app.hive_subscriptions hs
    JOIN hivemind_app.hive_accounts ha ON ha.id = hs.account_id
    JOIN hivemind_app.hive_communities hc ON hc.id = hs.community_id
    WHERE ha.name = _account AND hc.name = _community_name
    ), 0 );
    IF _check AND __subscription_id = 0 THEN
      RAISE EXCEPTION '% subscription on % does not exist', _account, _community_name USING ERRCODE = 'CEHM9';
    END IF;
  END IF;
  RETURN __subscription_id;
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
    SELECT current_block_num INTO __num FROM hive.hivemind_app_context_data_view;
    IF __num > 0 THEN
        SELECT created_at INTO __created_at FROM hive.hivemind_app_blocks_view WHERE num = __num;
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
