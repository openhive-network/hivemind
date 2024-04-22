--SELECT * FROM hivemind_helpers.get_community('hive-112345')
DROP FUNCTION IF EXISTS hivemind_helpers.get_community;
CREATE OR REPLACE FUNCTION hivemind_helpers.get_community(
  IN name TEXT,
  IN observer TEXT DEFAULT NULL
)
  RETURNS hivemind_app.bridge_api_community
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _name TEXT = hivemind_helpers.valid_community(name);
  _observer TEXT = hivemind_helpers.valid_account(observer,TRUE);
BEGIN
  RETURN (gc.id,
    gc.name,
    gc.title,
    gc.about,
    gc.lang,
    gc.type_id,
    gc.is_nsfw,
    gc.subscribers,
    gc.created_at,
    gc.sum_pending,
    gc.num_pending,
    gc.num_authors,
    gc.avatar_url,
    gc.description,
    gc.flag_text,
    gc.settings,
    gc.context,
    gc.team)::hivemind_app.bridge_api_community
  FROM hivemind_app.bridge_get_community(_name, _observer) gc
;

END;
$BODY$
;

DROP TYPE IF EXISTS hivemind_helpers.community_context CASCADE;
CREATE TYPE hivemind_helpers.community_context AS (
  role TEXT, 
  subscribed BOOLEAN,
  title TEXT
);

--SELECT * FROM hivemind_helpers.get_community_context('hive-112345','good-karma')
DROP FUNCTION IF EXISTS hivemind_helpers.get_community_context;
CREATE OR REPLACE FUNCTION hivemind_helpers.get_community_context(
  IN name TEXT,
  IN account TEXT DEFAULT NULL
)
  RETURNS hivemind_helpers.community_context
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _name TEXT = hivemind_helpers.valid_community(name);
  _account TEXT = hivemind_helpers.valid_account(account);
BEGIN
  RETURN (role, subscribed, title)::hivemind_helpers.community_context
  FROM json_to_record((SELECT * FROM hivemind_app.bridge_get_community_context(_account, _name))) as x(role TEXT, subscribed BOOLEAN, title text)
;

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.list_top_communities;
CREATE OR REPLACE FUNCTION hivemind_helpers.list_top_communities(IN "limit" INT DEFAULT 25)
  RETURNS SETOF JSONB
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _limit INT = hivemind_helpers.valid_limit("limit", 100, 25);
BEGIN
  RETURN QUERY (
    SELECT jsonb_build_array(hc.name, hc.title)
    FROM hivemind_app.hive_communities hc
    WHERE hc.rank > 0 ORDER BY hc.rank LIMIT _limit
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.list_pop_communities;
CREATE OR REPLACE FUNCTION hivemind_helpers.list_pop_communities(IN "limit" INT DEFAULT 25)
  RETURNS SETOF JSONB
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _limit INT = hivemind_helpers.valid_limit("limit", 25, 25);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(name, title) FROM hivemind_app.bridge_list_pop_communities( _limit )
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.list_all_subscriptions;
CREATE OR REPLACE FUNCTION hivemind_helpers.list_all_subscriptions(IN account TEXT)
  RETURNS SETOF JSONB
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _account TEXT = hivemind_helpers.valid_account(account);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(name, role, title, role_title) FROM hivemind_app.bridge_list_all_subscriptions(_account)
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.list_subscribers;
CREATE OR REPLACE FUNCTION hivemind_helpers.list_subscribers(
  IN community TEXT,
  IN "last" TEXT DEFAULT '',
  IN "limit" INT DEFAULT 100
)
  RETURNS SETOF JSONB
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _community TEXT = hivemind_helpers.valid_community(community);
  _last TEXT = hivemind_helpers.valid_account("last", TRUE);
  _limit INT = hivemind_helpers.valid_limit("limit", 100, 100);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(
      name, 
      role, 
      title, 
      hivemind_helpers.json_date(created_at))
    FROM hivemind_app.bridge_list_subscribers( _community, _last, _limit)
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.list_communities;
CREATE OR REPLACE FUNCTION hivemind_helpers.list_communities(
  IN "last" TEXT DEFAULT '',
  IN "limit" INT DEFAULT 100,
  IN query TEXT DEFAULT NULL,
  IN sort TEXT DEFAULT 'rank',
  IN observer TEXT DEFAULT NULL
)
  RETURNS SETOF hivemind_app.bridge_api_list_communities
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _supported_sort_list TEXT[] = ARRAY['rank', 'new', 'subs'];
  _last TEXT = hivemind_helpers.valid_account("last", TRUE);
  _limit INT = hivemind_helpers.valid_limit("limit", 100, 100);
  _observer TEXT = hivemind_helpers.valid_account(observer, TRUE);
BEGIN
  IF NOT (sort = ANY(_supported_sort_list)) THEN
    RAISE EXCEPTION 'Unsupported sort, valid sorts: %', _supported_sort_list;
  END IF;

  RETURN QUERY EXECUTE format(
    $query$

  	SELECT 
      id INTEGER,
      name VARCHAR(16),
      title VARCHAR(32),
      about VARCHAR(120),
      lang CHAR(2),
      type_id SMALLINT,
      is_nsfw BOOLEAN,
      subscribers INTEGER,
      sum_pending INTEGER,
      num_pending INTEGER,
      num_authors INTEGER,
      created_at VARCHAR(19),
      avatar_url VARCHAR(1024),
      context JSON,
      (CASE WHEN admins[1] IS NULL THEN '{}' ELSE admins END)
    FROM hivemind_app.bridge_list_communities_by_%I( %s, %s, %s, %s::INT);

    $query$,
    sort, _observer, _last, query, _limit
  ) res;

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_helpers.list_community_roles;
CREATE OR REPLACE FUNCTION hivemind_helpers.list_community_roles(
  IN community TEXT,
  IN "last" TEXT DEFAULT '',
  IN "limit" INT DEFAULT 50
)
  RETURNS SETOF JSONB
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _community TEXT = hivemind_helpers.valid_community(community);
  _last TEXT = hivemind_helpers.valid_account("last", TRUE);
  _limit INT = hivemind_helpers.valid_limit("limit", 100, 50);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(name, role, title) FROM hivemind_app.bridge_list_community_roles( _community, _last, _limit) 
);

END;
$BODY$
;
