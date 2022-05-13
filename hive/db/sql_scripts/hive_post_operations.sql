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
if _parent_author != '' THEN
  RETURN QUERY INSERT INTO hivemind_app.hive_posts as hp
  (parent_id, depth, community_id, category_id,
    root_id, is_muted, is_valid,
    author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend, active, payout_at, cashout_time, counter_deleted, block_num, block_num_created)
  SELECT php.id AS parent_id, php.depth + 1 AS depth,
      (CASE
          WHEN _block_num > _community_support_start_block THEN
            COALESCE(php.community_id, (select hc.id from hivemind_app.hive_communities hc where hc.name = _parent_permlink))
          ELSE NULL
      END) AS community_id,
      COALESCE(php.category_id, (select hcg.id from hivemind_app.hive_category_data hcg where hcg.category = _parent_permlink)) AS category_id,
      (CASE(php.root_id)
          WHEN 0 THEN php.id
          ELSE php.root_id
        END) AS root_id,
      php.is_muted AS is_muted, php.is_valid AS is_valid,
      ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
      _date AS updated_at,
      hivemind_app.calculate_time_part_of_hot(_date) AS sc_hot,
      hivemind_app.calculate_time_part_of_trending(_date) AS sc_trend,
      _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0,
        _block_num as block_num, _block_num as block_num_created
  FROM hivemind_app.hive_accounts ha,
        hivemind_app.hive_permlink_data hpd,
        hivemind_app.hive_posts php
  INNER JOIN hivemind_app.hive_accounts pha ON pha.id = php.author_id
  INNER JOIN hivemind_app.hive_permlink_data phpd ON phpd.id = php.permlink_id
  WHERE pha.name = _parent_author AND phpd.permlink = _parent_permlink AND
          ha.name = _author AND hpd.permlink = _permlink AND php.counter_deleted = 0

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

  RETURN QUERY INSERT INTO hivemind_app.hive_posts as hp
  (parent_id, depth, community_id, category_id,
    root_id, is_muted, is_valid,
    author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend,
    active, payout_at, cashout_time, counter_deleted, block_num, block_num_created,
    tags_ids)
  SELECT 0 AS parent_id, 0 AS depth,
      (CASE
        WHEN _block_num > _community_support_start_block THEN
          (select hc.id FROM hivemind_app.hive_communities hc WHERE hc.name = _parent_permlink)
        ELSE NULL
      END) AS community_id,
      (SELECT hcg.id FROM hivemind_app.hive_category_data hcg WHERE hcg.category = _parent_permlink) AS category_id,
      0 as root_id, -- will use id as root one if no parent
      false AS is_muted, true AS is_valid,
      ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
      _date AS updated_at,
      hivemind_app.calculate_time_part_of_hot(_date) AS sc_hot,
      hivemind_app.calculate_time_part_of_trending(_date) AS sc_trend,
      _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0
      , _block_num as block_num, _block_num as block_num_created
      , (
          SELECT ARRAY_AGG( prepare_tags )
          FROM hivemind_app.prepare_tags( ARRAY_APPEND(_metadata_tags, _parent_permlink ) )
        ) as tags_ids
  FROM hivemind_app.hive_accounts ha,
        hivemind_app.hive_permlink_data hpd
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

DROP FUNCTION IF EXISTS hivemind_app.delete_hive_post(character varying,character varying,character varying, integer, timestamp)
;
CREATE OR REPLACE FUNCTION hivemind_app.delete_hive_post(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _block_num hivemind_app.hive_blocks.num%TYPE,
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

END
$function$
;
