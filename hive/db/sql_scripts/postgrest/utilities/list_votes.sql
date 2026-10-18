DROP TYPE IF EXISTS hivemind_postgrest_utilities.vote_presentation CASCADE;
CREATE TYPE hivemind_postgrest_utilities.vote_presentation AS ENUM( 'database_api', 'condenser_api', 'bridge_api', 'active_votes', 'bridge_list_votes');

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.apply_vote_presentation;
CREATE FUNCTION hivemind_postgrest_utilities.apply_vote_presentation(IN _vote RECORD, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS
$function$
BEGIN
  IF _presentation_mode = 'condenser_api' THEN
    RETURN jsonb_build_object(
      'percent', _vote.percent::TEXT,
      'reputation', _vote.reputation,
      'rshares', hivemind_app.json_stringify_numeric(_vote.rshares),
      'voter', _vote.voter
    );
  ELSIF _presentation_mode = 'database_api' THEN
    RETURN jsonb_build_object(
      'voter', _vote.voter,
      'author', _vote.author,
      'permlink', _vote.permlink,
      'weight', hivemind_app.json_stringify_numeric(_vote.weight),
      'rshares', hivemind_app.json_stringify_numeric(_vote.rshares),
      'vote_percent', _vote.percent,
      'last_update', hivemind_postgrest_utilities.json_date(to_timestamp(_vote.last_update::TEXT, 'YYYY-MM-DD"T"HH24:MI:SS')::TIMESTAMP),
      'num_changes', _vote.num_changes
    );
  ELSIF _presentation_mode = 'bridge_api' THEN
    RETURN jsonb_build_object(
      'rshares', hivemind_app.json_stringify_numeric(_vote.rshares),
      'voter', _vote.voter
    );
  ELSIF _presentation_mode = 'active_votes' THEN
    RETURN jsonb_build_object(
      'percent', _vote.percent,
      'reputation', _vote.reputation,
      'rshares', hivemind_app.json_stringify_numeric(_vote.rshares),
      'voter', _vote.voter,
      'time', hivemind_postgrest_utilities.json_date(to_timestamp(_vote.last_update::TEXT, 'YYYY-MM-DD"T"HH24:MI:SS')::TIMESTAMP),
      'weight', hivemind_app.json_stringify_numeric(_vote.weight)
    )::jsonb;
  ELSIF _presentation_mode = 'bridge_list_votes' THEN
    RETURN jsonb_build_object(
      'voter', _vote.voter,
      'rshares', hivemind_app.json_stringify_numeric(_vote.rshares),
      'percent', _vote.percent,
      'weight', hivemind_app.json_stringify_numeric(_vote.weight),
      'time', hivemind_postgrest_utilities.json_date(to_timestamp(_vote.last_update::TEXT, 'YYYY-MM-DD"T"HH24:MI:SS')::TIMESTAMP),
      'reputation', hivemind_postgrest_utilities.rep_log10(_vote.reputation)
    );
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('create_votes_json_array - unspecified vote presentation mode');
  END IF;
END;
$function$
;

DROP TYPE IF EXISTS hivemind_postgrest_utilities.list_votes_case CASCADE;
CREATE TYPE hivemind_postgrest_utilities.list_votes_case AS ENUM( 'get_votes_for_posts', 'database_list_by_comment_voter', 'database_list_by_voter_comment', 'bridge_list_by_comment_voter_after');

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_votes;
CREATE FUNCTION hivemind_postgrest_utilities.list_votes(IN _observer_id INTEGER, IN _post_id INT, IN _limit INT, IN _case hivemind_postgrest_utilities.list_votes_case, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation, IN _voter_id INT DEFAULT NULL, IN _start_author_id INT DEFAULT NULL, IN _start_permlink_id INT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$function$
DECLARE
_result JSONB;
-- folded to a constant in the per-execution plan, so the planner drops the reputation join when it is not output
_with_reputation BOOLEAN := _presentation_mode NOT IN ('bridge_api', 'database_api');
BEGIN
  IF _case = ANY(ARRAY['database_list_by_comment_voter'::hivemind_postgrest_utilities.list_votes_case,'database_list_by_voter_comment'::hivemind_postgrest_utilities.list_votes_case,'bridge_list_by_comment_voter_after'::hivemind_postgrest_utilities.list_votes_case]) THEN
    assert _voter_id IS NOT NULL;
  END IF;
  IF _case = 'database_list_by_voter_comment' THEN
    assert _start_author_id IS NOT NULL AND _start_permlink_id IS NOT NULL;
  END IF;

  -- Dynamic SQL is planned with the parameter values on every execution: a generic plan of the
  -- CASE-in-WHERE statement scans all of hive_votes. A function-level SET plan_cache_mode would also
  -- apply to apply_vote_presentation and force it to replan its expressions for every vote.
  EXECUTE $query$
    SELECT jsonb_agg( -- list_votes
        hivemind_postgrest_utilities.apply_vote_presentation(r, $5)
      ) FROM (
      SELECT
        ha_v.name AS voter,
        ha_a.name AS author,
        hpd.permlink,
        v.weight,
        v.rshares,
        v.vote_percent AS percent,
        v.last_update,
        v.num_changes,
        (CASE WHEN $7 THEN ha_v.reputation END) AS reputation
      -- hive_votes_view joined inline: by_voter_comment pages on hive_votes.author_id, which the view does not expose
      FROM
        hivemind_app.hive_votes AS v
        JOIN hivemind_app.hive_accounts_view ha_v ON ha_v.id = v.voter_id
        JOIN hivemind_app.hive_accounts ha_a ON ha_a.id = v.author_id
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = v.permlink_id
      WHERE
      ( CASE
          WHEN $4 = 'get_votes_for_posts' THEN v.post_id = $2
          WHEN $4 = 'database_list_by_comment_voter' THEN (v.post_id = $2 AND v.voter_id >= $6)
          -- (author_id, permlink_id) order lets hive_votes_voter_id_author_id_permlink_id_uk bound the scan
          WHEN $4 = 'database_list_by_voter_comment' THEN (v.voter_id = $6 AND (v.author_id, v.permlink_id) >= ($8, $9))
          WHEN $4 = 'bridge_list_by_comment_voter_after' THEN (v.post_id = $2 AND v.voter_id > $6)
        END
      )
      AND ($1 = 0 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = $1 AND muted_id = v.voter_id))
      ORDER BY
      ( CASE
          WHEN $4 = 'get_votes_for_posts' THEN v.voter_id
          WHEN $4 = 'database_list_by_comment_voter' THEN v.voter_id
          WHEN $4 = 'database_list_by_voter_comment' THEN v.author_id
          WHEN $4 = 'bridge_list_by_comment_voter_after' THEN v.voter_id
        END
      ),
      ( CASE
          WHEN $4 = 'database_list_by_voter_comment' THEN v.permlink_id
        END
      )
      LIMIT $3
    ) r
  $query$
  INTO _result
  USING _observer_id, _post_id, _limit, _case, _presentation_mode, _voter_id, _with_reputation, _start_author_id, _start_permlink_id;

  RETURN COALESCE(_result, '[]'::jsonb);
END;
$function$
;
