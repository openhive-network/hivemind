DROP FUNCTION IF EXISTS hivemind_app.prepare_tags;
CREATE OR REPLACE FUNCTION hivemind_app.prepare_tags( in _raw_tags VARCHAR[] )
RETURNS SETOF hivemind_app.hive_tag_data.id%TYPE
LANGUAGE 'plpgsql'
VOLATILE
AS
$function$
DECLARE
   __i INTEGER;
   __tags VARCHAR[];
   __tag VARCHAR;
BEGIN
  FOR __i IN 1 .. ARRAY_UPPER( _raw_tags, 1)
  LOOP
    __tag = CAST( LEFT(LOWER(REGEXP_REPLACE( _raw_tags[ __i ], '[#\s]', '', 'g' )),32) as VARCHAR);
    CONTINUE WHEN __tag = '' OR __tag = ANY(__tags);
    __tags = ARRAY_APPEND( __tags, __tag );
  END LOOP;

  RETURN QUERY INSERT INTO
     hivemind_app.hive_tag_data AS htd(tag)
  SELECT UNNEST( __tags )
  ON CONFLICT("tag") DO UPDATE SET tag=EXCLUDED.tag --trick to always return id
  RETURNING htd.id;
END
$function$;


CREATE OR REPLACE FUNCTION encode_bitwise_mask(muted_reasons INT[])
    RETURNS INT AS $$
DECLARE
    mask INT := 0;
    number INT;
BEGIN
    FOREACH number IN ARRAY muted_reasons
        LOOP
            mask := mask | (1 << number);
        END LOOP;
    RETURN mask;
END;
$$ LANGUAGE plpgsql;

DROP TYPE IF EXISTS hivemind_app.process_community_post_result CASCADE;
CREATE TYPE hivemind_app.process_community_post_result AS (
    is_muted bool,
    community_id integer, -- hivemind_app.hive_posts.community_id%TYPE
    muted_reasons INTEGER
);

DROP FUNCTION IF EXISTS hivemind_app.process_community_post;
CREATE OR REPLACE FUNCTION hivemind_app.process_community_post(_block_num hivemind_app.hive_posts.block_num%TYPE, _community_support_start_block hivemind_app.hive_posts.block_num%TYPE, _parent_permlink hivemind_app.hive_permlink_data.permlink%TYPE, _author_id hivemind_app.hive_posts.author_id%TYPE, _is_comment bool, _is_parent_muted bool, _community_id hivemind_app.hive_posts.community_id%TYPE)
RETURNS hivemind_app.process_community_post_result
LANGUAGE plpgsql
as
    $$
declare
        __community_type_id SMALLINT;
        __role_id SMALLINT;
        __member_role CONSTANT SMALLINT := 2;
        __community_type_topic CONSTANT SMALLINT := 1;
        __community_type_journal CONSTANT SMALLINT := 2;
        __community_type_council CONSTANT SMALLINT := 3;
        __is_muted BOOL := TRUE;
        __community_id hivemind_app.hive_posts.community_id%TYPE;
        __muted_reasons INTEGER[] := ARRAY[]::INTEGER[];
BEGIN
        IF _block_num < _community_support_start_block THEN
            __is_muted := FALSE;
            __community_id := NULL;
        ELSE
            IF _is_comment = TRUE THEN
                SELECT type_id, id INTO __community_type_id, __community_id from hivemind_app.hive_communities where id = _community_id;
            ELSE
                SELECT type_id, id INTO __community_type_id, __community_id from hivemind_app.hive_communities where name = _parent_permlink;
            END IF;

            IF __community_id IS NOT NULL THEN
                IF __community_type_id = __community_type_topic THEN
                    __is_muted := FALSE;
                ELSE
                    IF __community_type_id = __community_type_journal AND _is_comment = TRUE THEN
                        __is_muted := FALSE;
                    ELSE
                        select role_id into __role_id from hivemind_app.hive_roles where hivemind_app.hive_roles.community_id = __community_id AND account_id = _author_id;
                        IF __community_type_id = __community_type_journal AND _is_comment = FALSE AND __role_id IS NOT NULL AND __role_id >= __member_role THEN
                            __is_muted := FALSE;
                        ELSIF __community_type_id = __community_type_council AND __role_id IS NOT NULL AND __role_id >= __member_role THEN
                            __is_muted := FALSE;
                        ELSE
                            -- This means the post was muted because of community reasons, 1 is MUTED_COMMUNITY_TYPE see community.py for the ENUM definition
                            __muted_reasons := ARRAY[1];
                        END IF;
                    END IF;
                END IF;
            ELSE
                __is_muted := FALSE;
            END IF;

            -- __is_muted can be TRUE here if it's a comment and its parent is muted
            IF _is_parent_muted = TRUE THEN
                __is_muted := TRUE;
                -- 2 is MUTED_PARENT, see community.py for the ENUM definition
                __muted_reasons := array_append(__muted_reasons, 2);
            END IF;

        END IF;

        RETURN (__is_muted, __community_id, encode_bitwise_mask(__muted_reasons))::hivemind_app.process_community_post_result;
    END;
$$ STABLE;

DROP FUNCTION IF EXISTS hivemind_app.process_hive_post_operation;
;
CREATE OR REPLACE FUNCTION hivemind_app.process_hive_post_operation(
    in _author hivemind_app.hive_accounts.name%TYPE,
    in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
    in _parent_author hivemind_app.hive_accounts.name%TYPE,
    in _parent_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
    in _date hivemind_app.hive_posts.created_at%TYPE,
    in _community_support_start_block hivemind_app.hive_posts.block_num%TYPE,
    in _block_num hivemind_app.hive_posts.block_num%TYPE,
    in _metadata_tags VARCHAR[])
    RETURNS TABLE (is_new_post boolean, id hivemind_app.hive_posts.id%TYPE, author_id hivemind_app.hive_posts.author_id%TYPE, permlink_id hivemind_app.hive_posts.permlink_id%TYPE,
                   post_category hivemind_app.hive_category_data.category%TYPE, parent_id hivemind_app.hive_posts.parent_id%TYPE, community_id hivemind_app.hive_posts.community_id%TYPE,
                   is_valid hivemind_app.hive_posts.is_valid%TYPE, is_muted hivemind_app.hive_posts.is_muted%TYPE, depth hivemind_app.hive_posts.depth%TYPE)
    LANGUAGE plpgsql
AS
$function$
BEGIN

    INSERT INTO hivemind_app.hive_permlink_data
    (permlink)
    values
        (
            _permlink
        )
    ON CONFLICT DO NOTHING
    ;
    IF _parent_author != '' THEN
        RETURN QUERY INSERT INTO hivemind_app.hive_posts as hp
            (parent_id, depth, community_id, category_id,
             root_id, is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend, active, payout_at, cashout_time, counter_deleted, block_num, block_num_created, muted_reasons)
            SELECT
                s.parent_id,
                s.depth,
                (s.composite).community_id,
                s.category_id,
                s.root_id,
                (s.composite).is_muted,
                s.is_valid,
                s.author_id,
                s.permlink_id,
                s.created_at,
                s.updated_at,
                s.sc_hot,
                s.sc_trend,
                s.active,
                s.payout_at,
                s.cashout_time,
                s.counter_deleted,
                s.block_num,
                s.block_num_created,
                (s.composite).muted_reasons
            FROM (
                     SELECT
                         hivemind_app.process_community_post(_block_num, _community_support_start_block, _parent_permlink, ha.id, TRUE, php.is_muted, php.community_id) as composite,
                         php.id AS parent_id, php.depth + 1 AS depth,
                         COALESCE(php.category_id, (select hcg.id from hivemind_app.hive_category_data hcg where hcg.category = _parent_permlink)) AS category_id,
                         (CASE(php.root_id)
                              WHEN 0 THEN php.id
                              ELSE php.root_id
                             END) AS root_id,
                         php.is_valid AS is_valid,
                         ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
                         _date AS updated_at,
                         hivemind_app.calculate_time_part_of_hot(_date) AS sc_hot,
                         hivemind_app.calculate_time_part_of_trending(_date) AS sc_trend,
                         _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time,
                         0 AS counter_deleted,
                         _block_num as block_num, _block_num as block_num_created
                     FROM hivemind_app.hive_accounts ha,
                          hivemind_app.hive_permlink_data hpd,
                          hivemind_app.hive_posts php
                              INNER JOIN hivemind_app.hive_accounts pha ON pha.id = php.author_id
                              INNER JOIN hivemind_app.hive_permlink_data phpd ON phpd.id = php.permlink_id
                     WHERE pha.name = _parent_author AND phpd.permlink = _parent_permlink AND
                         ha.name = _author AND hpd.permlink = _permlink AND php.counter_deleted = 0
                 ) s
            ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
                --- During post update it is disallowed to change: parent-post, category, community-id
                --- then also depth, is_valid and is_muted is impossible to change
                --- post edit part
                updated_at = _date,
                active = _date,
                block_num = _block_num
            RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, (SELECT hcd.category FROM hivemind_app.hive_category_data hcd WHERE hcd.id = hp.category_id) as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth
        ;
    ELSE
        INSERT INTO hivemind_app.hive_category_data
        (category)
        VALUES (_parent_permlink)
        ON CONFLICT (category) DO NOTHING
        ;

        RETURN QUERY
            WITH posts_data_to_insert AS MATERIALIZED (
                SELECT
                    s.parent_id,
                    s.depth,
                    (s.composite).community_id,
                    s.category_id,
                    s.root_id,
                    (s.composite).is_muted,
                    s.is_valid,
                    s.author_id,
                    s.permlink_id,
                    s.created_at,
                    s.updated_at,
                    s.sc_hot,
                    s.sc_trend,
                    s.active,
                    s.payout_at,
                    s.cashout_time,
                    s.counter_deleted,
                    s.block_num,
                    s.block_num_created,
                    (s.composite).muted_reasons
                FROM (
                         SELECT
                             hivemind_app.process_community_post(_block_num, _community_support_start_block, _parent_permlink, ha.id, FALSE,FALSE, NULL) as composite,
                             0 AS parent_id, 0 AS depth,
                             (SELECT hcg.id FROM hivemind_app.hive_category_data hcg WHERE hcg.category = _parent_permlink) AS category_id,
                             0 as root_id, -- will use id as root one if no parent
                             true AS is_valid,
                             ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
                             _date AS updated_at,
                             hivemind_app.calculate_time_part_of_hot(_date) AS sc_hot,
                             hivemind_app.calculate_time_part_of_trending(_date) AS sc_trend,
                             _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time,
                             0 AS counter_deleted,
                             _block_num as block_num, _block_num as block_num_created
                         FROM
                             hivemind_app.hive_accounts ha,
                             hivemind_app.hive_permlink_data hpd
                         WHERE ha.name = _author and hpd.permlink = _permlink
                     ) s
            ), -- posts_data_to_insert
                inserted_post AS MATERIALIZED (
                    INSERT INTO hivemind_app.hive_posts as hp
                        (parent_id, depth, community_id, category_id,
                         root_id, is_muted, is_valid,
                         author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend,
                         active, payout_at, cashout_time, counter_deleted, block_num, block_num_created, muted_reasons) -- removed tagsids
                        SELECT
                            pdi.parent_id,
                            pdi.depth,
                            pdi.community_id,
                            pdi.category_id,
                            pdi.root_id,
                            pdi.is_muted,
                            pdi.is_valid,
                            pdi.author_id,
                            pdi.permlink_id,
                            pdi.created_at,
                            pdi.updated_at,
                            pdi.sc_hot,
                            pdi.sc_trend,
                            pdi.active,
                            pdi.payout_at,
                            pdi.cashout_time,
                            pdi.counter_deleted,
                            pdi.block_num,
                            pdi.block_num_created,
                            pdi.muted_reasons
                        FROM posts_data_to_insert as pdi
                        ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
                            --- During post update it is disallowed to change: parent-post, category, community-id
                            --- then also depth, is_valid and is_muted is impossible to change
                            --- post edit part
                            updated_at = _date,
                            active = _date,
                            block_num = _block_num
                        RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, _parent_permlink as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth
                ) -- WITH inserted_post
            , tagsid_and_posts AS MATERIALIZED (
                SELECT prepare_tags FROM hivemind_app.prepare_tags( ARRAY_APPEND(_metadata_tags, _parent_permlink ) )
            ) -- WITH tagsid_and_posts
               , deleted_post_tags AS MATERIALIZED (
                DELETE FROM hivemind_app.hive_post_tags hp
                    USING hivemind_app.hive_post_tags as hpt
                    JOIN inserted_post as ip ON hpt.post_id = ip.id AND NOT ip.is_new_post
                    LEFT JOIN tagsid_and_posts as tap ON tap.prepare_tags = hpt.tag_id
                    WHERE hpt.post_id = hp.post_id AND tap.prepare_tags IS NULL
                    RETURNING hpt.post_id
            ) -- WITH deleted_post_tags
               , inserts_to_posts_and_tags AS MATERIALIZED (
                INSERT INTO hivemind_app.hive_post_tags(post_id, tag_id)
                    SELECT ip.id, tags.prepare_tags
                    FROM inserted_post as ip
                    LEFT JOIN deleted_post_tags as dpt ON dpt.post_id = 0 -- there is no post 0, this is only to force execute the deleted_post_tags CTE
                    JOIN tagsid_and_posts as tags ON TRUE
                ON CONFLICT DO NOTHING
            )
            SELECT
                ip.is_new_post,
                ip.id,
                ip.author_id,
                ip.permlink_id,
                ip.post_category,
                ip.parent_id,
                ip.community_id,
                ip.is_valid,
                ip.is_muted,
                ip.depth
            FROM inserted_post as ip;
    END IF;
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_app.delete_hive_post(character varying,character varying,character varying, integer, timestamp)
;
CREATE OR REPLACE FUNCTION hivemind_app.delete_hive_post(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _block_num hivemind_app.blocks_view.num%TYPE,
  in _date hivemind_app.hive_posts.active%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN

  __account_id = hivemind_app.find_account_id( _author, False );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, False );

  IF __post_id = 0 THEN
    RETURN;
  END IF;

  UPDATE hivemind_app.hive_posts
  SET counter_deleted =
  (
      SELECT max( hps.counter_deleted ) + 1
      FROM hivemind_app.hive_posts hps
      INNER JOIN hivemind_app.hive_permlink_data hpd ON hps.permlink_id = hpd.id
      WHERE hps.author_id = __account_id AND hpd.permlink = _permlink
  )
  ,block_num = _block_num
  ,active = _date
  WHERE id = __post_id;

  DELETE FROM hivemind_app.hive_reblogs
  WHERE post_id = __post_id;

  DELETE FROM hivemind_app.hive_feed_cache
  WHERE post_id = __post_id AND account_id = __account_id;

  DELETE FROM hivemind_app.hive_post_tags
  WHERE post_id = __post_id;

END
$function$
;
