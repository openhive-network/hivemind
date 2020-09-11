DROP VIEW IF EXISTS public.hive_accounts_info_view;

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
          select max(hp.created_at)
          FROM hive_posts hp
          WHERE ha.id=hp.author_id
        ),
        '1970-01-01 00:00:00.0'
      ),
      COALESCE(
        (
          select max(hv.last_update)
          from hive_votes hv
          WHERE ha.id=hv.voter_id
        ),
        '1970-01-01 00:00:00.0'
      )
    )
  ) active_at,
  display_name,
  about,
  reputation,
  profile_image,
  location,
  website,
  cover_image,
  rank,
  following,
  followers,
  proxy,
  proxy_weight,
  lastread_at,
  cached_at,
  raw_json
FROM
  hive_accounts ha
;