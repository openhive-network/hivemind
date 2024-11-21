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

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_communities_by_rank;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_communities_by_rank(IN _account_id INT, IN _community_id INT, IN _search TEXT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$function$
DECLARE
  _rank hivemind_app.hive_communities.rank%TYPE = 0;
BEGIN
  IF _community_id <> 0 THEN
    SELECT hc.rank INTO _rank FROM hivemind_app.hive_communities hc WHERE hc.id = _community_id;
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(jsonb_strip_nulls(to_jsonb(row))) FROM
      (
        SELECT
          hc.id,
          hc.name,
          COALESCE(NULLIF(hc.title,''),CONCAT('@',hc.name))::VARCHAR(32) AS title,
          hc.about,
          hc.lang,
          hc.type_id,
          hc.is_nsfw,
          hc.subscribers,
          hc.sum_pending,
          hc.num_pending,
          hc.num_authors,
          hc.created_at::VARCHAR(19),
          hc.avatar_url,
          (
            CASE
              WHEN _account_id <> 0 THEN hivemind_postgrest_utilities.get_community_context(_account_id, hivemind_postgrest_utilities.find_community_id(hc.name, True))
              ELSE '{}'::JSONB
            END
          ) AS context,
          (
            CASE
              WHEN COUNT(ha.name) <> 0 THEN jsonb_agg(ha.name ORDER BY ha.name)
              ELSE NULL
            END
          ) AS admins
        FROM hivemind_app.hive_communities hc
        LEFT JOIN hivemind_app.hive_roles hr ON hr.community_id = hc.id AND hr.role_id = 6
        LEFT JOIN hivemind_app.hive_accounts ha ON hr.account_id = ha.id
        WHERE
          hc.rank > _rank
          AND NOT(_search IS NOT NULL AND NOT to_tsvector('english', hc.title || ' ' || hc.about) @@ plainto_tsquery(_search))
        GROUP BY hc.id
        ORDER BY hc.rank ASC
        LIMIT _limit
      ) row
    ),
    '[]'::jsonb
  );
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_communities_by_new;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_communities_by_new(IN _account_id INT, IN _community_id INT, IN _search TEXT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$function$
BEGIN
  RETURN COALESCE(
    (
      SELECT jsonb_agg(jsonb_strip_nulls(to_jsonb(row))) FROM
      (
        SELECT
          hc.id,
          hc.name,
          COALESCE(NULLIF(hc.title,''),CONCAT('@',hc.name))::VARCHAR(32) AS title,
          hc.about,
          hc.lang,
          hc.type_id,
          hc.is_nsfw,
          hc.subscribers,
          hc.sum_pending,
          hc.num_pending,
          hc.num_authors,
          hc.created_at::VARCHAR(19),
          hc.avatar_url,
          (
            CASE
              WHEN _account_id <> 0 THEN hivemind_postgrest_utilities.get_community_context(_account_id, hivemind_postgrest_utilities.find_community_id(hc.name, True))
              ELSE '{}'::JSONB
            END
          ) AS context,
          (
            CASE
              WHEN COUNT(ha.name) <> 0 THEN jsonb_agg(ha.name ORDER BY ha.name)
              ELSE NULL
            END
          ) AS admins
        FROM hivemind_app.hive_communities hc
        LEFT JOIN hivemind_app.hive_roles hr ON hr.community_id = hc.id AND hr.role_id = 6
        LEFT JOIN hivemind_app.hive_accounts ha ON hr.account_id = ha.id
        WHERE
          NOT (_community_id <> 0 AND hc.id >= _community_id)
          AND NOT (_search IS NOT NULL AND NOT to_tsvector('english', hc.title || ' ' || hc.about) @@ plainto_tsquery(_search))
        GROUP BY hc.id
        ORDER BY hc.id DESC
        LIMIT _limit
      ) row
    ),
    '[]'::jsonb
  );
END
$function$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_communities_by_subs;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.list_communities_by_subs(IN _account_id INT, IN _community_id INT, IN _search TEXT, IN _limit INT)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$function$
DECLARE
  _subscribers hivemind_app.hive_communities.subscribers%TYPE;
BEGIN
  IF ( _community_id <> 0 ) THEN
    SELECT hc.subscribers INTO _subscribers FROM hivemind_app.hive_communities hc WHERE hc.id = _community_id;
  END IF;

  RETURN COALESCE(
    (
      SELECT jsonb_agg(jsonb_strip_nulls(to_jsonb(row))) FROM
      (
        SELECT
          hc.id,
          hc.name,
          COALESCE(NULLIF(hc.title,''),CONCAT('@',hc.name))::VARCHAR(32) AS title,
          hc.about,
          hc.lang,
          hc.type_id,
          hc.is_nsfw,
          hc.subscribers,
          hc.sum_pending,
          hc.num_pending,
          hc.num_authors,
          hc.created_at::VARCHAR(19),
          hc.avatar_url,
          (
            CASE
              WHEN _account_id <> 0 THEN hivemind_postgrest_utilities.get_community_context(_account_id, hivemind_postgrest_utilities.find_community_id(hc.name, True))
              ELSE '{}'::JSONB
            END
          ) AS context,
          (
            CASE
              WHEN COUNT(ha.name) <> 0 THEN jsonb_agg(ha.name ORDER BY ha.name)
              ELSE NULL
            END
          ) AS admins
        FROM hivemind_app.hive_communities hc
        LEFT JOIN hivemind_app.hive_roles hr ON hr.community_id = hc.id AND hr.role_id = 6
        LEFT JOIN hivemind_app.hive_accounts ha ON hr.account_id = ha.id
        WHERE 
          NOT (_community_id <> 0 AND hc.subscribers >= _subscribers AND NOT (hc.subscribers = _subscribers AND hc.id < _community_id))
          AND NOT(_search IS NOT NULL AND NOT to_tsvector('english', hc.title || ' ' || hc.about) @@ plainto_tsquery(_search))
        GROUP BY hc.id
        ORDER BY hc.subscribers DESC, hc.id DESC
        LIMIT _limit
      ) row
    ),
    '[]'::jsonb
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