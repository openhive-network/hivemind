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
