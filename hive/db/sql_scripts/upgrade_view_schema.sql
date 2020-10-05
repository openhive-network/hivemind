CREATE OR REPLACE VIEW hive_votes_view
AS
SELECT
    hv.id,
    hv.voter_id as voter_id,
    ha_a.name as author,
    hpd.permlink as permlink,
    vote_percent as percent,
    ha_v.reputation as reputation,
    rshares,
    last_update,
    ha_v.name as voter,
    weight,
    num_changes,
    hv.permlink_id as permlink_id,
    post_id,
    is_effective
FROM
    hive_votes hv
INNER JOIN hive_accounts ha_v ON ha_v.id = hv.voter_id
INNER JOIN hive_accounts ha_a ON ha_a.id = hv.author_id
INNER JOIN hive_permlink_data hpd ON hpd.id = hv.permlink_id
;

CREATE OR REPLACE VIEW public.hive_accounts_info_view
AS
SELECT
  id,
  name,
  (
    select count(*) post_count
    FROM hive_posts hp
    WHERE ha.id=hp.author_id
  ) post_count,
  created_at,
  (
    SELECT GREATEST
    (
      created_at,
      COALESCE(
        (
          select max(hp.created_at + '0 days'::interval)
          FROM hive_posts hp
          WHERE ha.id=hp.author_id
        ),
        '1970-01-01 00:00:00.0'
      ),
      COALESCE(
        (
          select max(hv.last_update + '0 days'::interval)
          from hive_votes hv
          WHERE ha.id=hv.voter_id
        ),
        '1970-01-01 00:00:00.0'
      )
    )
  ) active_at,
  reputation,
  rank,
  following,
  followers,
  lastread_at,
  posting_json_metadata,
  json_metadata
FROM
  hive_accounts ha
;
