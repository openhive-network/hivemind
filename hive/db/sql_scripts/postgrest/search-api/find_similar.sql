DROP FUNCTION IF EXISTS hivemind_endpoints.search_api_find_similar;
CREATE OR REPLACE FUNCTION hivemind_endpoints.search_api_find_similar(
    _params jsonb,
    _votes_mode SMALLINT DEFAULT 0)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    STABLE PARALLEL UNSAFE
AS $BODY$
DECLARE
    -- more_like_this term selection; a starting point, not tuned for relevance.
    _MIN_TERM_FREQUENCY CONSTANT INT = 2;
    _MIN_DOC_FREQUENCY CONSTANT INT = 5;
    _MAX_QUERY_TERMS CONSTANT INT = 25;
    _limit INT;
    _post_id INT;
    _observer_id INT;
    _truncate_body INT;
    _top_votes INT;
    _result JSONB;
    _candidate_ids INT[];
    _candidate_scores REAL[];
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(_params, (CASE WHEN _votes_mode = 0 THEN '{"author": "string", "permlink": "string", "limit": "number", "observer": "string", "truncate_body": "number"}'
                                                                   ELSE '{"author": "string", "permlink": "string", "limit": "number", "observer": "string", "top_votes": "number", "truncate_body": "number"}' END)::JSON, 2, '{"permlink": "permlink must be string"}');

    _post_id = hivemind_postgrest_utilities.find_comment_id(
            hivemind_postgrest_utilities.valid_account(
                    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'author', True), False),
            hivemind_postgrest_utilities.valid_permlink(
                    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'permlink', True), False),
            True);

    _limit = hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False),
                                                       least(20, hivemind_postgrest_utilities.get_max_posts_per_call_limit()),
                                                       1, hivemind_postgrest_utilities.get_max_posts_per_call_limit(), 'limit');

    _observer_id = hivemind_postgrest_utilities.find_account_id(
            hivemind_postgrest_utilities.valid_account(
                    hivemind_postgrest_utilities.parse_argument_from_json(_params, 'observer', False),
                /* allow_empty */ True ), True);

    _top_votes = (CASE
        WHEN _votes_mode = 0 THEN 0
        ELSE hivemind_postgrest_utilities.valid_number(hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'top_votes', False), 0, 0, 10, 'top_votes')
    END);

    _truncate_body =
            hivemind_postgrest_utilities.valid_number(
                    hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'truncate_body', False),
                    0, NULL, NULL, 'truncate_body');

    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_search') THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(
            'Full-text search is not available (pg_search extension not installed)');
    END IF;

    -- Only top-level posts are in the BM25 index; a comment has no document to compare.
    IF NOT hivemind_app.is_top_level_post(_post_id) THEN
        RETURN '[]'::jsonb;
    END IF;

    -- is_top_level_post(hpd.id) restates the partial BM25 index predicate: without it
    -- pg_search 0.25.3 spends seconds and raises "Unsupported query shape".
    -- more_like_this takes the post by key_value: its `document` overload expects a JSON
    -- fields document, not the post's text.
    -- The statement runs through EXECUTE so that it gets a one-shot custom plan with the
    -- post id and limit as constants, which pg_search needs to push the ORDER BY ... LIMIT
    -- down as a TopK scan (see find_text). Ordering ties by id keeps the result stable
    -- among equal scores. The candidate limit over-fetches to leave room for posts of
    -- muted authors.
    -- The post itself is excluded outside the LIMIT rather than by `hpd.id <> $1`: pg_search
    -- pushes that down as `exists(id) AND NOT term(id)`, which adds 0 or 1 to a document's
    -- score depending on how the index build laid out its segments, so independent builds
    -- of the same data ranked the candidates differently. The post matches itself, so the
    -- candidate limit leaves room for it.
    -- Scores are rounded before ranking: the same document's score differs in its last
    -- float bit between index builds (segments sum it in a different order), so two posts
    -- with equal scores would otherwise rank by that noise instead of by id.
    -- Parameters: $1 post id, $2 candidate limit, $3..$5 the more_like_this constants.
    EXECUTE $sql$
        SELECT array_agg(c.id), array_agg(round(c.score::numeric, 4)::real)
        FROM (
            SELECT hpd.id, paradedb.score(hpd.id) AS score
            FROM hivemind_app.hive_post_data hpd
            WHERE hpd @@@ pdb.more_like_this(key_value => $1, fields => ARRAY['title', 'body'],
                                             min_term_frequency => $3, min_doc_frequency => $4,
                                             max_query_terms => $5)
              AND hivemind_app.is_top_level_post(hpd.id)
            ORDER BY paradedb.score(hpd.id) DESC, hpd.id DESC
            LIMIT $2
        ) c
        WHERE c.id <> $1
        $sql$
        INTO _candidate_ids, _candidate_scores
        USING _post_id, _limit * 2 + 1, _MIN_TERM_FREQUENCY, _MIN_DOC_FREQUENCY, _MAX_QUERY_TERMS;

    _result = (
        SELECT jsonb_agg (
                       hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, NULL, row.is_pinned, True, NULL, _votes_mode, _top_votes)
               ) FROM (
                      WITH similar_posts AS (
                               SELECT c.id, c.score
                               FROM unnest(_candidate_ids, _candidate_scores) AS c(id, score)
                           ),
                           not_muted_posts as (
                               SELECT sp.id,
                                      ROW_NUMBER() OVER (ORDER BY sp.score DESC, sp.id DESC)::int AS rank_order
                               FROM   similar_posts sp
                                          JOIN hivemind_app.hive_posts hp ON hp.id = sp.id
                               WHERE  (_observer_id = 0 OR NOT EXISTS (
                                   SELECT 1
                                   FROM   hivemind_app.muted_accounts_by_id_view
                                   WHERE  observer_id = _observer_id AND muted_id = hp.author_id))
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
                      FROM not_muted_posts nmp,
                           LATERAL hivemind_app.get_full_post_view_by_id(nmp.id, _observer_id) hp
                      ORDER BY nmp.rank_order ASC
                      LIMIT _limit
                  ) row
    );

    RETURN COALESCE(_result, '[]'::jsonb);
END
$BODY$;
