DROP FUNCTION IF EXISTS prepare_tags;
CREATE OR REPLACE FUNCTION prepare_tags( in _raw_tags VARCHAR[] )
RETURNS SETOF hive_tag_data.id%TYPE
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
     hive_tag_data AS htd(tag)
  SELECT UNNEST( __tags )
  ON CONFLICT("tag") DO UPDATE SET tag=EXCLUDED.tag --trick to always return id
  RETURNING htd.id;
END
$function$;

DROP FUNCTION IF EXISTS process_community_post;
CREATE OR REPLACE FUNCTION process_community_post(_block_num hive_posts.block_num%TYPE, _community_support_start_block hive_posts.block_num%TYPE, _community_id hive_posts.community_id%TYPE, _community_name hive_permlink_data.permlink%TYPE, _author_id hive_posts.author_id%TYPE, is_comment bool)
RETURNS TABLE(is_muted bool, community_id hive_posts.community_id%TYPE)
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
BEGIN
        IF _block_num < _community_support_start_block THEN
            RETURN QUERY ( SELECT FALSE, NULL::integer);
            RETURN; -- extra return because a RETURN QUERY does not end the function
        END IF;

        -- TODO: probably can be cleaned up with only one query instead of the IF
        IF _community_id IS NOT NULL THEN
            SELECT type_id INTO __community_type_id FROM hive_communities WHERE id = _community_id;
        ELSE
            SELECT type_id, id INTO __community_type_id, _community_id from hive_communities where name = _community_name;
        END IF;

        IF __community_type_id = __community_type_topic THEN
            RETURN QUERY ( SELECT TRUE, _community_id); -- Community type 1 allows everyone to post & comment
            RETURN; -- extra return because a RETURN QUERY does not end the function
        ELSE
            IF __community_type_id = __community_type_journal AND is_comment = TRUE THEN
                RETURN QUERY ( SELECT TRUE, _community_id); -- Community type journal allows everyone to comment
                RETURN; -- extra return because a RETURN QUERY does not end the function
            END IF;
            select role_id into __role_id from hive_roles where hive_roles.community_id = _community_id AND account_id = _author_id;
            IF __community_type_id = __community_type_journal AND is_comment = FALSE AND __role_id IS NOT NULL AND __role_id >= __member_role THEN
                RETURN QUERY ( SELECT TRUE, _community_id); -- You have to be at least a member to post
                RETURN; -- extra return because a RETURN QUERY does not end the function
            ELSIF __community_type_id = __community_type_council AND __role_id IS NOT NULL AND __role_id >= __member_role THEN
                RETURN QUERY ( SELECT TRUE, _community_id); -- You have to be at least a member to post or comment
                RETURN; -- extra return because a RETURN QUERY does not end the function
            END IF;
        END IF;
        RETURN QUERY ( SELECT FALSE, _community_id);
    END;
$$;

DROP FUNCTION IF EXISTS process_hive_post_operation;
;
CREATE OR REPLACE FUNCTION process_hive_post_operation(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _parent_author hive_accounts.name%TYPE,
  in _parent_permlink hive_permlink_data.permlink%TYPE,
  in _date hive_posts.created_at%TYPE,
  in _community_support_start_block hive_posts.block_num%TYPE,
  in _block_num hive_posts.block_num%TYPE,
  in _metadata_tags VARCHAR[])
RETURNS TABLE (is_new_post boolean, id hive_posts.id%TYPE, author_id hive_posts.author_id%TYPE, permlink_id hive_posts.permlink_id%TYPE,
                post_category hive_category_data.category%TYPE, parent_id hive_posts.parent_id%TYPE, community_id hive_posts.community_id%TYPE,
                is_valid hive_posts.is_valid%TYPE, is_muted hive_posts.is_muted%TYPE, depth hive_posts.depth%TYPE)
LANGUAGE plpgsql
AS
$function$
BEGIN

INSERT INTO hive_permlink_data
(permlink)
values
(
_permlink
)
ON CONFLICT DO NOTHING
;
if _parent_author != '' THEN
  RETURN QUERY INSERT INTO hive_posts as hp
  (parent_id, depth, community_id, category_id,
    root_id, is_muted, is_valid,
    author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend, active, payout_at, cashout_time, counter_deleted, block_num, block_num_created)
  SELECT php.id AS parent_id, php.depth + 1 AS depth,
      pcp.community_id AS community_id,
      COALESCE(php.category_id, (select hcg.id from hive_category_data hcg where hcg.category = _parent_permlink)) AS category_id,
      (CASE(php.root_id)
          WHEN 0 THEN php.id
          ELSE php.root_id
        END) AS root_id,
      pcp.is_muted AS is_muted,
      php.is_valid AS is_valid,
      ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
      _date AS updated_at,
      calculate_time_part_of_hot(_date) AS sc_hot,
      calculate_time_part_of_trending(_date) AS sc_trend,
      _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0,
        _block_num as block_num, _block_num as block_num_created
  FROM hive_accounts ha,
        hive_permlink_data hpd,
        process_community_post(_block_num, _community_support_start_block, NULL, _parent_permlink, ha.id, false) pcp,
        hive_posts php
  INNER JOIN hive_accounts pha ON pha.id = php.author_id
  INNER JOIN hive_permlink_data phpd ON phpd.id = php.permlink_id
  WHERE pha.name = _parent_author AND phpd.permlink = _parent_permlink AND
          ha.name = _author AND hpd.permlink = _permlink AND php.counter_deleted = 0

  ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
    --- During post update it is disallowed to change: parent-post, category, community-id
    --- then also depth, is_valid and is_muted is impossible to change
    --- post edit part
    updated_at = _date,
    active = _date,
    block_num = _block_num
  RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, (SELECT hcd.category FROM hive_category_data hcd WHERE hcd.id = hp.category_id) as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth
;
ELSE
  INSERT INTO hive_category_data
  (category)
  VALUES (_parent_permlink)
  ON CONFLICT (category) DO NOTHING
  ;

  RETURN QUERY INSERT INTO hive_posts as hp
  (parent_id, depth, community_id, category_id,
    root_id, is_muted, is_valid,
    author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend,
    active, payout_at, cashout_time, counter_deleted, block_num, block_num_created,
    tags_ids)
  SELECT 0 AS parent_id, 0 AS depth,
      pcp.community_id AS community_id,
      (SELECT hcg.id FROM hive_category_data hcg WHERE hcg.category = _parent_permlink) AS category_id,
      0 as root_id, -- will use id as root one if no parent
      pcp.is_muted AS is_muted, true AS is_valid,
      ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
      _date AS updated_at,
      calculate_time_part_of_hot(_date) AS sc_hot,
      calculate_time_part_of_trending(_date) AS sc_trend,
      _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0
      , _block_num as block_num, _block_num as block_num_created
      , (
          SELECT ARRAY_AGG( prepare_tags )
          FROM prepare_tags( ARRAY_APPEND(_metadata_tags, _parent_permlink ) )
        ) as tags_ids
  FROM hive_accounts ha,
        process_community_post(_block_num, _community_support_start_block, NULL, _parent_permlink, author_id, false) pcp,
        hive_permlink_data hpd
  WHERE ha.name = _author and hpd.permlink = _permlink

  ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
    --- During post update it is disallowed to change: parent-post, category, community-id
    --- then also depth, is_valid and is_muted is impossible to change
    --- post edit part
    updated_at = _date,
    active = _date,
    block_num = _block_num,
    tags_ids = EXCLUDED.tags_ids

  RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, _parent_permlink as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth
  ;
END IF;
END
$function$
;

DROP FUNCTION if exists delete_hive_post(character varying,character varying,character varying, integer, timestamp)
;
CREATE OR REPLACE FUNCTION delete_hive_post(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _block_num hive_blocks.num%TYPE,
  in _date hive_posts.active%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN

  __account_id = find_account_id( _author, False );
  __post_id = find_comment_id( _author, _permlink, False );

  IF __post_id = 0 THEN
    RETURN;
  END IF;

  UPDATE hive_posts
  SET counter_deleted =
  (
      SELECT max( hps.counter_deleted ) + 1
      FROM hive_posts hps
      INNER JOIN hive_permlink_data hpd ON hps.permlink_id = hpd.id
      WHERE hps.author_id = __account_id AND hpd.permlink = _permlink
  )
  ,block_num = _block_num
  ,active = _date
  WHERE id = __post_id;

  DELETE FROM hive_reblogs
  WHERE post_id = __post_id;

  DELETE FROM hive_feed_cache
  WHERE post_id = __post_id AND account_id = __account_id;

END
$function$
;
