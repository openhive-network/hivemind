DROP FUNCTION if exists process_hive_post_operation(character varying,character varying,character varying,character varying,timestamp without time zone,integer,integer)
;
CREATE OR REPLACE FUNCTION process_hive_post_operation(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _parent_author hive_accounts.name%TYPE,
  in _parent_permlink hive_permlink_data.permlink%TYPE,
  in _date hive_posts.created_at%TYPE,
  in _community_support_start_block hive_posts.block_num%TYPE,
  in _block_num hive_posts.block_num%TYPE)
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
      (CASE
          WHEN _block_num > _community_support_start_block THEN
            COALESCE(php.community_id, (select hc.id from hive_communities hc where hc.name = _parent_permlink))
          ELSE NULL
      END) AS community_id,
      COALESCE(php.category_id, (select hcg.id from hive_category_data hcg where hcg.category = _parent_permlink)) AS category_id,
      (CASE(php.root_id)
          WHEN 0 THEN php.id
          ELSE php.root_id
        END) AS root_id,
      php.is_muted AS is_muted, php.is_valid AS is_valid,
      ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
      _date AS updated_at,
      calculate_time_part_of_hot(_date) AS sc_hot,
      calculate_time_part_of_trending(_date) AS sc_trend,
      _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0,
        _block_num as block_num, _block_num as block_num_created
  FROM hive_accounts ha,
        hive_permlink_data hpd,
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
    author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend, active, payout_at, cashout_time, counter_deleted, block_num, block_num_created)
  SELECT 0 AS parent_id, 0 AS depth,
      (CASE
        WHEN _block_num > _community_support_start_block THEN
          (select hc.id FROM hive_communities hc WHERE hc.name = _parent_permlink)
        ELSE NULL
      END) AS community_id,
      (SELECT hcg.id FROM hive_category_data hcg WHERE hcg.category = _parent_permlink) AS category_id,
      0 as root_id, -- will use id as root one if no parent
      false AS is_muted, true AS is_valid,
      ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
      _date AS updated_at,
      calculate_time_part_of_hot(_date) AS sc_hot,
      calculate_time_part_of_trending(_date) AS sc_trend,
      _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time, 0
      , _block_num as block_num, _block_num as block_num_created
  FROM hive_accounts ha,
        hive_permlink_data hpd
  WHERE ha.name = _author and hpd.permlink = _permlink

  ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
    --- During post update it is disallowed to change: parent-post, category, community-id
    --- then also depth, is_valid and is_muted is impossible to change
    --- post edit part
    updated_at = _date,
    active = _date,
    block_num = _block_num

  RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, _parent_permlink as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth
  ;
END IF;
END
$function$
;

DROP FUNCTION if exists delete_hive_post(character varying,character varying,character varying, integer)
;
CREATE OR REPLACE FUNCTION delete_hive_post(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE,
  in _block_num hive_blocks.num%TYPE)
RETURNS TABLE (id hive_posts.id%TYPE, depth hive_posts.depth%TYPE)
LANGUAGE plpgsql
AS
$function$
BEGIN
  RETURN QUERY UPDATE hive_posts AS hp
    SET counter_deleted =
    (
      SELECT max( hps.counter_deleted ) + 1
      FROM hive_posts hps
      INNER JOIN hive_accounts ha ON hps.author_id = ha.id
      INNER JOIN hive_permlink_data hpd ON hps.permlink_id = hpd.id
      WHERE ha.name = _author AND hpd.permlink = _permlink
    )
    , block_num = _block_num
  FROM hive_posts hp1
  INNER JOIN hive_accounts ha ON hp1.author_id = ha.id
  INNER JOIN hive_permlink_data hpd ON hp1.permlink_id = hpd.id
  WHERE hp.id = hp1.id AND ha.name = _author AND hpd.permlink = _permlink AND hp1.counter_deleted = 0
  RETURNING hp.id, hp.depth;
END
$function$
;
