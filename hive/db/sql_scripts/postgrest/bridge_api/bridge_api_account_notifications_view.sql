DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_notifications_view;
CREATE FUNCTION hivemind_endpoints.get_account_notifications_view(
    _account TEXT,
    _min_score INTEGER DEFAULT 25,
    _last_id BIGINT DEFAULT 0,
    _limit INTEGER DEFAULT 100
)
RETURNS TABLE(
    id TEXT,
    type TEXT,
    score INTEGER,
    date TIMESTAMP,
    msg TEXT,
    url TEXT
)
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account_id INT;
  _oldest_block INTEGER;
BEGIN
  IF _account IS NULL THEN
    RAISE EXCEPTION 'account parameter is required';
  END IF;

  _account_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_account, False),
    True
  );

  _min_score = hivemind_postgrest_utilities.valid_number(_min_score, 25, 0, 100, 'score');
  _last_id = hivemind_postgrest_utilities.valid_bigint(_last_id, 0, NULL, NULL, 'last_id');
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

  _oldest_block = hivemind_app.block_before_head( '90 days' );

  RETURN QUERY
  SELECT
    hnv.id::TEXT as id,
    hivemind_postgrest_utilities.get_notify_type_from_id(hnv.type_id) as type,
    hnv.score::INTEGER as score,
    hnv.created_at as date,
    hivemind_postgrest_utilities.get_notify_message(
      (hnv.id, hnv.type_id, hs.name, hd.name, ha.name, hpd.permlink, hnv.community, hnv.community_title, hnv.payload, hm.mentions)::hivemind_postgrest_utilities.notify_message_params
    ) as msg,
    CASE
      WHEN hpd.permlink <> '' THEN '@' || ha.name || '/' || hpd.permlink
      WHEN hnv.community <> '' THEN 'trending/' || hnv.community
      WHEN hs.name <> '' THEN '@' || hs.name
      WHEN hd.name <> '' THEN '@' || hd.name
    END as url
      FROM
      (
        SELECT
          nv.id,
          nv.type_id,
          nv.created_at,
          nv.score,
          nv.community,
          nv.community_title,
          COALESCE(nv.post_id, 0) AS post_id,
          nv.src,
          nv.dst,
          nv.payload
        FROM hivemind_app.hive_notification_cache nv
        WHERE
          nv.dst = _account_id
          AND nv.block_num > _oldest_block
          AND nv.score >= _min_score
          AND NOT( _last_id <> 0 AND nv.id >= _last_id )
        ORDER BY nv.id DESC
        LIMIT _limit
      ) hnv
  JOIN hivemind_app.hive_posts hp on hnv.post_id = hp.id
  JOIN hivemind_app.hive_accounts ha on hp.author_id = ha.id
  JOIN hivemind_app.hive_accounts hs on hs.id = hnv.src
  JOIN hivemind_app.hive_accounts hd on hd.id = hnv.dst
  JOIN hivemind_app.hive_permlink_data hpd on hp.permlink_id = hpd.id,
  lateral
  (
    SELECT
      CASE
          WHEN hnv.type_id != 16 THEN 0 --everything else than mentions (only optimization)
          ELSE hivemind_postgrest_utilities.get_number_of_mentions_in_post( hnv.post_id )
      END as mentions
  ) as hm;
END
$$
;
