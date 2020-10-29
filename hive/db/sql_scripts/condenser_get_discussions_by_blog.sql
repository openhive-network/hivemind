DROP TYPE IF EXISTS get_discussions_post CASCADE;
CREATE TYPE get_discussions_post AS (
  id INT,
  community_id INT,
  author VARCHAR(16),
  permlink VARCHAR(255),
  author_rep BIGINT,
  title VARCHAR(512),
  body TEXT,
  category VARCHAR(255),
  depth SMALLINT,
  promoted DECIMAL(10, 3),
  payout DECIMAL(10, 3),
  payout_at TIMESTAMP,
  pending_payout DECIMAL(10, 3),
  is_paidout BOOLEAN,
  children INT,
  votes INT,
  active_votes INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  rshares NUMERIC,
  json TEXT,
  is_hidden BOOLEAN,
  is_grayed BOOLEAN,
  total_votes BIGINT,
  parent_author VARCHAR(16),
  parent_permlink_or_category VARCHAR(255),
  curator_payout_value VARCHAR(30),
  root_author VARCHAR(16),
  root_permlink VARCHAR(255),
  max_accepted_payout VARCHAR(30),
  percent_hbd INT,
  allow_replies BOOLEAN,
  allow_votes BOOLEAN,
  allow_curation_rewards BOOLEAN,
  beneficiaries JSON,
  url TEXT,
  root_title VARCHAR(512)
);

DROP FUNCTION IF EXISTS get_created_at_for_post;
CREATE OR REPLACE FUNCTION get_created_at_for_post(
  in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE
)
RETURNS TIMESTAMP
AS
$function$
DECLARE
  __post_id INT;
  __timestamp TIMESTAMP;
BEGIN
  __post_id = find_comment_id(_author, _permlink, False);
  IF __post_id = 0 THEN
    RETURN current_timestamp;
  END IF;
  SELECT INTO __timestamp
    created_at
  FROM
    hive_posts hp
  WHERE
    hp.id = __post_id;
  RETURN __timestamp;
END
$function$
language 'plpgsql';

DROP FUNCTION IF EXISTS get_discussions_by_blog;

CREATE OR REPLACE FUNCTION get_discussions_by_blog(
  in _tag hive_accounts.name%TYPE,
  in _start_author hive_accounts.name%TYPE,
  in _start_permlink hive_permlink_data.permlink%TYPE,
  in _limit INT
)
RETURNS SETOF get_discussions_post
AS
$function$
DECLARE
  __created_at TIMESTAMP;
BEGIN
  __created_at = get_created_at_for_post(_start_author, _start_permlink);
  RETURN QUERY SELECT
        hp.id,
        hp.community_id,
        hp.author,
        hp.permlink,
        hp.author_rep,
        hp.title,
        hp.body,
        hp.category,
        hp.depth,
        hp.promoted,
        hp.payout,
        hp.payout_at,
        hp.pending_payout,
        hp.is_paidout,
        hp.children,
        hp.votes,
        hp.active_votes,
        hp.created_at,
        hp.updated_at,
        hp.rshares,
        hp.json,
        hp.is_hidden,
        hp.is_grayed,
        hp.total_votes,
        hp.parent_author,
        hp.parent_permlink_or_category,
        hp.curator_payout_value,
        hp.root_author,
        hp.root_permlink,
        hp.max_accepted_payout,
        hp.percent_hbd,
        hp.allow_replies,
        hp.allow_votes,
        hp.allow_curation_rewards,
        hp.beneficiaries,
        hp.url,
        hp.root_title,
        hp.is_muted
    FROM hive_posts_view hp
    INNER JOIN
    (
        SELECT
            post_id
        FROM
            hive_feed_cache hfc
        INNER JOIN hive_accounts hfc_ha ON hfc.account_id = hfc_ha.id
        INNER JOIN hive_posts hfc_hp ON hfc.post_id = hfc_hp.id
        WHERE
            hfc_ha.name = _tag
            AND hfc_hp.created_at <= __created_at
        ORDER BY
            hfc_hp.created_at DESC
        LIMIT _limit
    ) ds on ds.post_id = hp.id
    ORDER BY hp.created_at DESC;
END
$function$
language 'plpgsql';