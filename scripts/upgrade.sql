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

DROP FUNCTION IF EXISTS get_discussion
        ;
        CREATE OR REPLACE FUNCTION get_discussion(
            in _author hive_accounts.name%TYPE,
            in _permlink hive_permlink_data.permlink%TYPE
        )
        RETURNS TABLE
        (
            id hive_posts.id%TYPE, parent_id hive_posts.parent_id%TYPE, author hive_accounts.name%TYPE, permlink hive_permlink_data.permlink%TYPE,
            title hive_post_data.title%TYPE, body hive_post_data.body%TYPE, category hive_category_data.category%TYPE, depth hive_posts.depth%TYPE,
            promoted hive_posts.promoted%TYPE, payout hive_posts.payout%TYPE, pending_payout hive_posts.pending_payout%TYPE, payout_at hive_posts.payout_at%TYPE,
            is_paidout hive_posts.is_paidout%TYPE, children hive_posts.children%TYPE, created_at hive_posts.created_at%TYPE, updated_at hive_posts.updated_at%TYPE,
            rshares hive_posts_view.rshares%TYPE, abs_rshares hive_posts_view.abs_rshares%TYPE, json hive_post_data.json%TYPE, author_rep hive_accounts.reputation%TYPE,
            is_hidden hive_posts.is_hidden%TYPE, is_grayed hive_posts.is_grayed%TYPE, total_votes BIGINT, sc_trend hive_posts.sc_trend%TYPE,
            acct_author_id hive_posts.author_id%TYPE, root_author hive_accounts.name%TYPE, root_permlink hive_permlink_data.permlink%TYPE,
            parent_author hive_accounts.name%TYPE, parent_permlink_or_category hive_permlink_data.permlink%TYPE, allow_replies BOOLEAN,
            allow_votes hive_posts.allow_votes%TYPE, allow_curation_rewards hive_posts.allow_curation_rewards%TYPE, url TEXT, root_title hive_post_data.title%TYPE,
            beneficiaries hive_posts.beneficiaries%TYPE, max_accepted_payout hive_posts.max_accepted_payout%TYPE, percent_hbd hive_posts.percent_hbd%TYPE,
            curator_payout_value hive_posts.curator_payout_value%TYPE
        )
        LANGUAGE plpgsql
        AS
        $function$
        DECLARE
            __post_id INT;
        BEGIN
            __post_id = find_comment_id( _author, _permlink, True );
            RETURN QUERY
            SELECT
                hpv.id,
                hpv.parent_id,
                hpv.author,
                hpv.permlink,
                hpv.title,
                hpv.body,
                hpv.category,
                hpv.depth,
                hpv.promoted,
                hpv.payout,
                hpv.pending_payout,
                hpv.payout_at,
                hpv.is_paidout,
                hpv.children,
                hpv.created_at,
                hpv.updated_at,
                hpv.rshares,
                hpv.abs_rshares,
                hpv.json,
                hpv.author_rep,
                hpv.is_hidden,
                hpv.is_grayed,
                hpv.total_votes,
                hpv.sc_trend,
                hpv.author_id AS acct_author_id,
                hpv.root_author,
                hpv.root_permlink,
                hpv.parent_author,
                hpv.parent_permlink_or_category,
                hpv.allow_replies,
                hpv.allow_votes,
                hpv.allow_curation_rewards,
                hpv.url,
                hpv.root_title,
                hpv.beneficiaries,
                hpv.max_accepted_payout,
                hpv.percent_hbd,
                hpv.curator_payout_value
            FROM
            (
                WITH RECURSIVE child_posts (id, parent_id) AS
                (
                    SELECT hp.id, hp.parent_id
                    FROM hive_posts hp
                    WHERE hp.id = __post_id
                    AND NOT hp.is_muted
                    UNION ALL
                    SELECT children.id, children.parent_id
                    FROM hive_posts children
                    JOIN child_posts ON children.parent_id = child_posts.id
                    WHERE children.counter_deleted = 0 AND NOT children.is_muted
                )
                SELECT hp2.id
                FROM hive_posts hp2
                JOIN child_posts cp ON cp.id = hp2.id
                ORDER BY hp2.id
            ) ds
            JOIN hive_posts_view hpv ON ds.id = hpv.id
            ORDER BY ds.id
            LIMIT 2000
            ;
        END
        $function$
        ;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_trends;
CREATE FUNCTION bridge_get_ranked_post_by_trends( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
  __trending_limit FLOAT = -1.0;
BEGIN
    IF _author <> '' THEN
        __post_id = find_comment_id( _author, _permlink, True );
        SELECT hp.sc_trend INTO __trending_limit FROM hive_posts hp WHERE hp.id = __post_id;
    END IF;
    RETURN QUERY SELECT
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
FROM
    hive_posts hp1
WHERE NOT hp1.is_paidout AND hp1.depth = 0
    AND ( __post_id = -1 OR hp1.sc_trend < __trending_limit OR ( hp1.sc_trend = __trending_limit AND hp1.id < __post_id  ) )
ORDER BY hp1.sc_trend DESC
LIMIT _limit
   ) as trends
JOIN hive_posts_view hp ON hp.id = trends.id
ORDER BY trends.trend DESC, trends.id LIMIT _limit;
END
$function$
language plpgsql STABLE
;

DROP FUNCTION IF EXISTS bridge_get_ranked_post_by_created;
CREATE FUNCTION bridge_get_ranked_post_by_created( in _author VARCHAR, in _permlink VARCHAR, in _limit SMALLINT )
RETURNS SETOF bridge_api_post
AS
$function$
DECLARE
  __post_id INTEGER = -1;
BEGIN
  IF _author <> '' THEN
      __post_id = find_comment_id( _author, _permlink, True );
  END IF;
  RETURN QUERY SELECT
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
      , hp1.created_at as created_at
      FROM hive_posts hp1 WHERE hp1.depth = 0 AND NOT hp1.is_grayed AND ( __post_id = -1 OR hp1.id < __post_id  )
      ORDER BY hp1.id DESC
      LIMIT _limit
  ) as created
  JOIN hive_posts_view hp ON hp.id = created.id
  ORDER BY created.created_at DESC, created.id LIMIT _limit;
END
$function$
language plpgsql STABLE
;
