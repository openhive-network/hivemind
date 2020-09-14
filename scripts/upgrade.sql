DROP TYPE IF EXISTS bridge_api_post CASCADE;
CREATE TYPE bridge_api_post AS (
    id INTEGER,
    author VARCHAR,
    parent_author VARCHAR,
    author_rep FLOAT4,
    root_title VARCHAR,
    beneficiaries JSON,
    max_accepted_payout VARCHAR,
    percent_hbd INTEGER,
    url TEXT,
    permlink VARCHAR,
    parent_permlink_or_category VARCHAR,
    title VARCHAR,
    body TEXT,
    category VARCHAR,
    depth SMALLINT,
    promoted DECIMAL(10,3),
    payout DECIMAL(10,3),
    pending_payout DECIMAL(10,3),
    payout_at TIMESTAMP,
    is_paidout BOOLEAN,
    children INTEGER,
    votes INTEGER,
    created_at TIMESTAMP,
    updated_at TIMESTAMP,
    rshares NUMERIC,
    abs_rshares NUMERIC,
    json TEXT,
    is_hidden BOOLEAN,
    is_grayed BOOLEAN,
    total_votes BIGINT,
    sc_trend FLOAT4,
    role_title VARCHAR,
    community_title VARCHAR,
    role_id SMALLINT,
    is_pinned BOOLEAN,
    curator_payout_value VARCHAR
);

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends;
CREATE FUNCTION bridge_get_ranked_post_by_trends( in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
  SELECT
    hp.id,
    hp.author,
    hp.parent_author,
    hp.author_rep,
    hp.root_title,
    hp.beneficiaries,
    hp.max_accepted_payout,
    hp.percent_hbd,
    hp.url,
    hp.permlink,
    hp.parent_permlink_or_category,
    hp.title,
    hp.body,
    hp.category,
    hp.depth,
    hp.promoted,
    hp.payout,
    hp.pending_payout,
    hp.payout_at,
    hp.is_paidout,
    hp.children,
    hp.votes,
    hp.created_at,
    hp.updated_at,
    hp.rshares,
    hp.abs_rshares,
    hp.json,
    hp.is_hidden,
    hp.is_grayed,
    hp.total_votes,
    hp.sc_trend,
    hp.role_title,
    hp.community_title,
    hp.role_id,
    hp.is_pinned,
    hp.curator_payout_value
  FROM
  (
    SELECT
      hp1.id
    , hp1.sc_trend as trend
    FROM hive_posts hp1 WHERE NOT hp1.is_paidout AND hp1.depth = 0 ORDER BY hp1.sc_trend DESC LIMIT _limit
   ) as trends
   JOIN hive_posts_view hp ON hp.id = trends.id ORDER BY trends.trend DESC
$function$
language sql

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
