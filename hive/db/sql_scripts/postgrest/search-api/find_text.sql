DROP FUNCTION IF EXISTS hivemind_endpoints.search_api_find_text;
CREATE OR REPLACE FUNCTION hivemind_endpoints.search_api_find_text(
    _params jsonb)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
AS $BODY$
DECLARE
    _limit INT;
    _post_id INT;
    _observer_id INT;
    _pattern TEXT;
    _sort_type TEXT;
    _truncate_body INT;
    _result JSONB;
    _author_id INT;
    _search_query TEXT;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"pattern": "string", "sort": "string", "author": "string", "start_author": "string", "start_permlink": "string", "limit": "number", "observer": "string", "truncate_body": "number"}', 1, '{"start_permlink": "permlink must be string"}');

    _limit = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
                                                       least(20, hivemind_postgrest_utilities.get_max_posts_per_call_limit()),
                                                       1, hivemind_postgrest_utilities.get_max_posts_per_call_limit(), 'limit');

    _post_id = hivemind_postgrest_utilities.find_comment_id(
            hivemind_postgrest_utilities.valid_account(
                    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_author', False), True),
            hivemind_postgrest_utilities.valid_permlink(
                    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_permlink', False), True),
            True);

    _pattern = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'pattern', True);

    _observer_id = hivemind_postgrest_utilities.find_account_id(
            hivemind_postgrest_utilities.valid_account(
                    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False),
                /* allow_empty */ True ), True);

    _author_id = hivemind_postgrest_utilities.find_account_id(
            hivemind_postgrest_utilities.valid_account(
                    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', False),
                /* allow_empty */ True ), True);

    _truncate_body =
            hivemind_postgrest_utilities.valid_number(
                    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'truncate_body', False),
                    0, NULL, NULL, 'truncate_body');

    CASE hivemind_postgrest_utilities.parse_argument_from_json(_params, 'sort', True)
        WHEN 'relevance' THEN _sort_type = 'relevance';
        WHEN 'created' THEN _sort_type = 'created';
        ELSE RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Unsupported sort, valid sorts: relevance, created');
        END CASE;

    -- Build search query for ParadeDB using the preprocessor
    -- Handles: quoted phrases, +/- terms, field specifications, and escaping
    _search_query = hivemind_postgrest_utilities.preprocess_search_query(_pattern);
    
    -- If preprocessing returns empty (e.g., for empty input), return empty result
    IF _search_query = '' OR _search_query IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    -- Branch based on whether author is specified
    IF _author_id > 0 THEN
        -- Author-specific search: filter by author first, then search
        _result = (
            SELECT jsonb_agg (
                           hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, NULL, row.is_pinned, True)
                   ) FROM (
                              WITH -- Get all posts by the specified author
                                   author_posts AS (
                                       SELECT id
                                       FROM hivemind_app.hive_posts
                                       WHERE author_id = _author_id
                                         AND depth = 0
                                   ),
                                   -- Search within author's posts
                                   bm25_posts AS (
                                       SELECT
                                           hpd.id as id,
                                           CASE _sort_type
                                               WHEN 'relevance' THEN paradedb.score(hpd.id)
                                               ELSE 0
                                           END as score
                                       FROM hivemind_app.hive_post_data hpd
                                       INNER JOIN author_posts ap ON ap.id = hpd.id
                                       WHERE hpd @@@ paradedb.parse(_search_query)
                                       ORDER BY 
                                           CASE _sort_type
                                               WHEN 'relevance' THEN paradedb.score(hpd.id)
                                               ELSE hpd.id
                                           END DESC
                                       LIMIT _limit * 2  -- Reduced multiplier for better performance
                                   ),
                                   not_muted_posts as (
                                       SELECT bp.id, bp.score
                                       FROM   bm25_posts bp
                                                  JOIN hivemind_app.hive_posts hp ON hp.id = bp.id
                                       WHERE  (_observer_id = 0 OR NOT EXISTS (
                                           SELECT 1
                                           FROM   hivemind_app.muted_accounts_by_id_view
                                           WHERE  observer_id = _observer_id AND muted_id = hp.author_id))
                                   ),
                                   ordered_posts as (
                                       SELECT nmp.id,
                                              ROW_NUMBER() OVER (
                                                  ORDER BY 
                                                      CASE _sort_type
                                                          WHEN 'created' THEN nmp.id
                                                          ELSE nmp.score
                                                      END DESC,
                                                      nmp.id DESC
                                              ) AS rank_order,
                                              nmp.score
                                       FROM not_muted_posts nmp
                                   ),
                                   upper_bound as (
                                       SELECT op.rank_order AS from_order
                                       FROM   ordered_posts op
                                       WHERE  op.id = _post_id
                                   )
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
                                  hp.curator_payout_value,
                                  hp.is_muted,
                                  hp.source AS blacklists,
                                  hp.muted_reasons
                              FROM ordered_posts op,
                                   LATERAL hivemind_app.get_full_post_view_by_id(op.id, _observer_id) hp
                              WHERE  op.rank_order >
                                     COALESCE((SELECT from_order FROM upper_bound),0)
                              ORDER BY op.rank_order ASC
                              LIMIT _limit
                          ) row
        );
    ELSE
        -- General search: use BM25 with early limiting
        _result = (
            SELECT jsonb_agg (
                           hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, NULL, row.is_pinned, True)
                   ) FROM (
                              WITH -- find posts with BM25 search, LIMIT EARLY
                                   bm25_posts AS (
                                       SELECT
                                           hpd.id as id,
                                           CASE _sort_type
                                               WHEN 'relevance' THEN paradedb.score(hpd.id)
                                               ELSE 0
                                           END as score
                                       FROM hivemind_app.hive_post_data hpd
                                       WHERE hpd @@@ paradedb.parse(_search_query)
                                       ORDER BY 
                                           CASE _sort_type
                                               WHEN 'relevance' THEN paradedb.score(hpd.id)
                                               ELSE hpd.id
                                           END DESC
                                       LIMIT _limit * 2  -- Reduced multiplier for better performance
                                   ),
                                   not_muted_posts as (
                                       SELECT bp.id, bp.score
                                       FROM   bm25_posts bp
                                                  JOIN hivemind_app.hive_posts hp ON hp.id = bp.id
                                       WHERE  (_observer_id = 0 OR NOT EXISTS (
                                           SELECT 1
                                           FROM   hivemind_app.muted_accounts_by_id_view
                                           WHERE  observer_id = _observer_id AND muted_id = hp.author_id))
                                   ),
                               ordered_posts as (
                                   SELECT nmp.id,
                                          CASE _sort_type
                                              WHEN 'created' THEN
                                                          ROW_NUMBER() OVER (ORDER BY nmp.id DESC) -- newer first
                                              ELSE
                                                          ROW_NUMBER() OVER (ORDER BY nmp.score DESC, nmp.id DESC)
                                              END::int AS rank_order,
                                          nmp.score
                                   FROM not_muted_posts nmp
                               ),
                               upper_bound as ( -- find starting post (if passed) order
                                   SELECT op.rank_order AS from_order
                                   FROM   ordered_posts op
                                   WHERE  op.id = _post_id
                               )
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
                              hp.curator_payout_value,
                              hp.is_muted,
                              hp.source AS blacklists,
                              hp.muted_reasons
                          FROM ordered_posts op,
                               LATERAL hivemind_app.get_full_post_view_by_id(op.id, _observer_id) hp
                          WHERE  op.rank_order >
                                 COALESCE((SELECT from_order FROM upper_bound),0)
                          ORDER BY op.rank_order ASC
                          LIMIT _limit
                      ) row
        );
    END IF;

    RETURN COALESCE(_result, '[]'::jsonb);
END
$BODY$;