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
    _candidate_ids INT[];
    _candidate_scores REAL[];
    _candidate_limit INT;
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

    -- Check if pg_search extension is available (required for BM25 full-text search)
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_search') THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(
            'Full-text search is not available (pg_search extension not installed)');
    END IF;

    -- Build search query for ParadeDB using the preprocessor
    -- Handles: quoted phrases, +/- terms, field specifications, and escaping
    _search_query = hivemind_postgrest_utilities.preprocess_search_query(_pattern);
    
    -- If preprocessing returns empty (e.g., for empty input), return empty result
    IF _search_query = '' OR _search_query IS NULL THEN
        RETURN '[]'::jsonb;
    END IF;

    -- Candidate selection: each sort has its own statement so that pg_search sees a bare
    -- ORDER BY expression it can push into the BM25 index as a TopK scan. Never merge them
    -- back into one `ORDER BY CASE _sort_type ... END`: the CASE arms have different types,
    -- so the created key becomes (hpd.id)::real, which pg_search cannot push down; it then
    -- warns "Query has LIMIT ... but is not using Top K scan" and reads every match. On a
    -- mainnet node (136M posts, pg_search 0.25.3, pattern 'hive', limit 20) that took
    -- 33-138 s (3.35M heap fetches) versus 0.23 s with `ORDER BY hpd.id DESC`, past the 5 s
    -- statement_timeout of haf_api_node. Relevance survived only because a custom plan
    -- folds the CASE; a generic plan kept it and lost the TopK scan as well.
    -- The same holds for the LIMIT: a generic plan keeps `LIMIT _limit * 2` as an expression
    -- and loses the TopK scan, while a bare `LIMIT _candidate_limit` is pushed down. The
    -- author filter is an `id = ANY(array)` for the same reason: pg_search folds it into the
    -- index query as a term set, whereas a join to hive_posts leaves the LIMIT above the
    -- join and the scan reads every match (3.3M rows for 'hive').
    -- is_top_level_post(hpd.id) must match the partial bm25 index predicate
    -- (hive_post_data_bm25_idx WHERE is_top_level_post(id)). pg_search <=0.19.5 rejected an
    -- explicit predicate and inferred it; 0.21.13 reversed that and raises "Unsupported
    -- query shape" without it.
    -- The candidate limit over-fetches to leave room for posts of muted authors.
    _candidate_limit = _limit * 2;
    IF _author_id > 0 THEN
        IF _sort_type = 'relevance' THEN
            SELECT array_agg(c.id), array_agg(c.score) INTO _candidate_ids, _candidate_scores
            FROM (
                SELECT hpd.id, paradedb.score(hpd.id) AS score
                FROM hivemind_app.hive_post_data hpd
                WHERE hpd @@@ paradedb.parse(_search_query)
                  AND hivemind_app.is_top_level_post(hpd.id)
                  AND hpd.id = ANY(ARRAY(
                      SELECT hp.id FROM hivemind_app.hive_posts hp
                      WHERE hp.author_id = _author_id AND hp.depth = 0))
                ORDER BY paradedb.score(hpd.id) DESC
                LIMIT _candidate_limit
            ) c;
        ELSE
            SELECT array_agg(c.id) INTO _candidate_ids
            FROM (
                SELECT hpd.id
                FROM hivemind_app.hive_post_data hpd
                WHERE hpd @@@ paradedb.parse(_search_query)
                  AND hivemind_app.is_top_level_post(hpd.id)
                  AND hpd.id = ANY(ARRAY(
                      SELECT hp.id FROM hivemind_app.hive_posts hp
                      WHERE hp.author_id = _author_id AND hp.depth = 0))
                ORDER BY hpd.id DESC
                LIMIT _candidate_limit
            ) c;
        END IF;
    ELSE
        IF _sort_type = 'relevance' THEN
            SELECT array_agg(c.id), array_agg(c.score) INTO _candidate_ids, _candidate_scores
            FROM (
                SELECT hpd.id, paradedb.score(hpd.id) AS score
                FROM hivemind_app.hive_post_data hpd
                WHERE hpd @@@ paradedb.parse(_search_query)
                  AND hivemind_app.is_top_level_post(hpd.id)
                ORDER BY paradedb.score(hpd.id) DESC
                LIMIT _candidate_limit
            ) c;
        ELSE
            SELECT array_agg(c.id) INTO _candidate_ids
            FROM (
                SELECT hpd.id
                FROM hivemind_app.hive_post_data hpd
                WHERE hpd @@@ paradedb.parse(_search_query)
                  AND hivemind_app.is_top_level_post(hpd.id)
                ORDER BY hpd.id DESC
                LIMIT _candidate_limit
            ) c;
        END IF;
    END IF;

    _result = (
        SELECT jsonb_agg (
                       hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, NULL, row.is_pinned, True)
               ) FROM (
                      WITH -- _candidate_scores stays NULL for the created sort; unnest pads it with NULLs
                           bm25_posts AS (
                               SELECT c.id, c.score
                               FROM unnest(_candidate_ids, _candidate_scores) AS c(id, score)
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

    RETURN COALESCE(_result, '[]'::jsonb);
END
$BODY$;