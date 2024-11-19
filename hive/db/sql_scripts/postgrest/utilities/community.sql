DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_community_context;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_community_context(IN _account_id INT, _community_id INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$function$
DECLARE
  _subscribed BOOLEAN;
  _result JSONB;
BEGIN
  ASSERT _account_id <> 0;

  _subscribed = EXISTS(SELECT 1 FROM hivemind_app.hive_subscriptions WHERE account_id = _account_id AND community_id = _community_id);

  _result = (
    SELECT jsonb_build_object(
      'role', hivemind_postgrest_utilities.get_role_name(role_id),
      'subscribed', _subscribed,
      'title', title
    )
    FROM hivemind_app.hive_roles
    WHERE account_id = _account_id AND community_id = _community_id
  );

  RETURN COALESCE(
    _result,
    jsonb_build_object(
      'role', hivemind_postgrest_utilities.get_role_name(0),
      'subscribed', _subscribed,
      'title', ''
    )
  );
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_top_communities;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_top_communities(IN "limit" INT DEFAULT 25)
  RETURNS TABLE (community_data JSONB, rank INT)
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _limit INT = hivemind_postgrest_utilities.valid_limit("limit", 100, 25);
BEGIN
  RETURN QUERY (
    SELECT jsonb_build_array(hc.name, hc.title) AS community_data, hc.rank
    FROM hivemind_app.hive_communities hc
    WHERE hc.rank > 0 ORDER BY hc.rank LIMIT _limit
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_pop_communities;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_pop_communities(IN "limit" INT DEFAULT 25)
  RETURNS SETOF JSONB
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _limit INT = hivemind_postgrest_utilities.valid_limit("limit", 25, 25);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(name, title) FROM hivemind_app.bridge_list_pop_communities( _limit )
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_all_subscriptions;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_all_subscriptions(IN account TEXT)
  RETURNS SETOF JSONB
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
DECLARE
  _account TEXT = hivemind_postgrest_utilities.valid_account(account);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(name, role, title, role_title) FROM hivemind_app.bridge_list_all_subscriptions(_account)
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_subscribers;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_subscribers(
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
  _community TEXT = hivemind_postgrest_utilities.valid_community(community);
  _last TEXT = hivemind_postgrest_utilities.valid_account("last", TRUE);
  _limit INT = hivemind_postgrest_utilities.valid_limit("limit", 100, 100);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(
      name,
      role,
      title,
      hivemind_postgrest_utilities.json_date(created_at))
    FROM hivemind_app.bridge_list_subscribers( _community, _last, _limit)
);

END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_communities;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_communities(
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
  _last TEXT = hivemind_postgrest_utilities.valid_account("last", TRUE);
  _limit INT = hivemind_postgrest_utilities.valid_limit("limit", 100, 100);
  _observer TEXT = hivemind_postgrest_utilities.valid_account(observer, TRUE);
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

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_community_roles;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_community_roles(
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
  _community TEXT = hivemind_postgrest_utilities.valid_community(community);
  _last TEXT = hivemind_postgrest_utilities.valid_account("last", TRUE);
  _limit INT = hivemind_postgrest_utilities.valid_limit("limit", 100, 50);
BEGIN
  RETURN QUERY (
		SELECT jsonb_build_array(name, role, title) FROM hivemind_app.bridge_list_community_roles( _community, _last, _limit)
);

END;
$BODY$
;
