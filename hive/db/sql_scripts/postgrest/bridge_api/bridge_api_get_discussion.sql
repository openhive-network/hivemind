DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_discussion;


CREATE FUNCTION hivemind_endpoints.bridge_api_get_discussion(IN _params JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$$
DECLARE
  -- for extracting the parameters as parsed from the JSON-RPC
  _author     TEXT;
  _permlink   TEXT;
  _observer   TEXT;
  _params_len INT;

  -- after extracting the parameters, look up the database ids they represent and store the results here: 
  _post_id    INT;
  _observer_id INT;
BEGIN
  ---------------------------------------------------------------------------
  -- 1. Handle null or unexpected input
  ---------------------------------------------------------------------------
  IF _params IS NULL THEN
    RAISE EXCEPTION 'Missing JSON-RPC params';
  END IF;

  ---------------------------------------------------------------------------
  -- 2. Distinguish between object vs. array
  ---------------------------------------------------------------------------
  IF jsonb_typeof(_params) = 'object' THEN
    -- If an object, assume named parameters directly
    _author   = _params->>'author';
    _permlink = _params->>'permlink';
    _observer = _params->>'observer';

  ELSIF jsonb_typeof(_params) = 'array' THEN
    -- If an array, could be:
    --   (A) Positional params: ["author","permlink","observer"?]
    --   (B) Single-object array: [{"author":"...","permlink":"...","observer":"..."}]
    
    _params_len = jsonb_array_length(_params);

    -- (B) Single-object array?
    --     If length=1 and the first element is an object, treat that object as our param set
    IF _params_len = 1 AND jsonb_typeof(_params->0) = 'object' THEN
      _author   = (_params->0)->>'author';
      _permlink = (_params->0)->>'permlink';
      _observer = (_params->0)->>'observer';

    ELSE
      -- (A) Otherwise, treat them as positional arguments
      IF _params_len < 2 THEN
        RAISE EXCEPTION 'Need at least 2 parameters: author, permlink. (3rd observer is optional)';
      END IF;

      -- Because jsonb->>N returns TEXT, you can directly assign
      _author   = _params->>0;
      _permlink = _params->>1;

      IF _params_len >= 3 THEN
        _observer = _params->>2;
      END IF;
    END IF;

  ELSE
    RAISE EXCEPTION 'params is neither an object nor an array';
  END IF;

  ---------------------------------------------------------------------------
  -- 3. Validate we have at least author/permlink; observer is optional
  ---------------------------------------------------------------------------
  -- EMF: we don't really need to do this,the False parameter to valid_account/valid_permlink
  --      will raise an exception if they're NULL or empty, the only benefit of doing it here
  --      is we might be able to issue a slightly better error message
  -- 
  -- IF _author IS NULL OR _author = '' THEN
  --   RAISE EXCEPTION 'Missing or empty "author" parameter';
  -- END IF;
  -- IF _permlink IS NULL OR _permlink = '' THEN
  --   RAISE EXCEPTION 'Missing or empty "permlink" parameter';
  -- END IF;
  -- _observer is optional, so no error needed if NULL.

  ---------------------------------------------------------------------------
  -- 4. Now do the usual lookups/validations
  ---------------------------------------------------------------------------
  _post_id = hivemind_postgrest_utilities.find_comment_id(
    hivemind_postgrest_utilities.valid_account(_author, False),
    hivemind_postgrest_utilities.valid_permlink(_permlink, False),
    True
  );

  _observer_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account(_observer, True),
    True
  );

  ---------------------------------------------------------------------------
  -- 5. Return same final JSON as before
  --    (the actual discussion data)
  ---------------------------------------------------------------------------
  RETURN COALESCE(
  (
    SELECT     -- bridge_api_get_discussion
      jsonb_object_agg((row.author || '/' || row.permlink), hivemind_postgrest_utilities.create_bridge_post_object(row, 0, NULL, row.is_pinned, True, row.replies))
      FROM (
        SELECT
          hpv.id,
          hpv.author,
          hpv.parent_author,
          hpv.author_rep,
          hpv.root_title,
          hpv.beneficiaries,
          hpv.max_accepted_payout,
          hpv.percent_hbd,
          hpv.url,
          hpv.permlink,
          hpv.parent_permlink_or_category,
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
          hpv.votes,
          hpv.created_at,
          hpv.updated_at,
          hpv.rshares,
          hpv.abs_rshares,
          hpv.json,
          hpv.is_hidden,
          hpv.is_grayed,
          hpv.total_votes,
          hpv.sc_trend,
          hpv.role_title,
          hpv.community_title,
          hpv.role_id,
          hpv.is_pinned,
          hpv.curator_payout_value,
          hpv.is_muted,
          hpv.parent_id,
          hpv.source AS blacklists,
          hpv.muted_reasons,
          ds.replies
        FROM
        (
          WITH RECURSIVE child_posts (id, parent_id) AS
          (
            SELECT
              hp.id,
              hp.parent_id,
              NULL::TEXT COLLATE "C" AS reply
            FROM hivemind_app.live_posts_comments_view hp 
            WHERE 
              hp.id = _post_id
              AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))

            UNION ALL

            SELECT
              children.id,
              children.parent_id,
              ha.name || '/' || hp.permlink  AS reply
            FROM hivemind_app.live_posts_comments_view children
            JOIN child_posts ON children.parent_id = child_posts.id
            JOIN hivemind_app.hive_accounts ha ON children.author_id = ha.id AND (NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = children.author_id))
            JOIN hivemind_app.hive_permlink_data hp ON hp.id = children.permlink_id
          ),
          post_replies AS
          (
            SELECT
              parent_id,
              jsonb_agg(reply ORDER BY id) AS replies
            FROM child_posts
            GROUP BY parent_id
          )
          SELECT
            cp.id,
            r.replies
          FROM child_posts cp
          LEFT JOIN post_replies r ON r.parent_id = cp.id
          ORDER BY cp.id
        ) ds,
          LATERAL hivemind_app.get_full_post_view_by_id(ds.id, _observer_id) hpv
        ORDER BY ds.id
        LIMIT 2000
    ) row),
  '{}') ;
END
$$;
