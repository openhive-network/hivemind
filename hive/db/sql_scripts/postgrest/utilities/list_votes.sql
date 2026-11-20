DROP TYPE IF EXISTS hivemind_postgrest_utilities.vote_presentation CASCADE;
CREATE TYPE hivemind_postgrest_utilities.vote_presentation AS ENUM( 'database_api', 'condenser_api', 'bridge_api', 'active_votes', 'bridge_list_votes');

DROP TYPE IF EXISTS hivemind_postgrest_utilities.list_votes_case CASCADE;
CREATE TYPE hivemind_postgrest_utilities.list_votes_case AS ENUM( 'get_votes_for_posts', 'database_list_by_comment_voter', 'database_list_by_voter_comment', 'bridge_list_by_comment_voter_after', 'list_by_voter_last_update_before');

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_votes;
CREATE FUNCTION hivemind_postgrest_utilities.list_votes(IN _observer_id INTEGER, IN _post_id INT, IN _limit INT, IN _case hivemind_postgrest_utilities.list_votes_case, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation, IN _voter_id INT DEFAULT NULL, IN _start_author_id INT DEFAULT NULL, IN _start_permlink_id INT DEFAULT NULL, IN _before_last_update TIMESTAMP DEFAULT NULL, IN _before_vote_id BIGINT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$function$
DECLARE
_result JSONB;
BEGIN
  IF _presentation_mode IS NULL THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('create_votes_json_array - unspecified vote presentation mode');
  END IF;
  IF _case = ANY(ARRAY['database_list_by_comment_voter'::hivemind_postgrest_utilities.list_votes_case,'database_list_by_voter_comment'::hivemind_postgrest_utilities.list_votes_case,'bridge_list_by_comment_voter_after'::hivemind_postgrest_utilities.list_votes_case,'list_by_voter_last_update_before'::hivemind_postgrest_utilities.list_votes_case]) THEN
    assert _voter_id IS NOT NULL;
  END IF;
  IF _case = 'database_list_by_voter_comment' THEN
    assert _start_author_id IS NOT NULL AND _start_permlink_id IS NOT NULL;
  END IF;
  IF _case = 'list_by_voter_last_update_before' THEN
    assert _before_last_update IS NOT NULL AND _before_vote_id IS NOT NULL;
  END IF;

  -- Dynamic SQL is planned with the parameter values on every execution: a generic plan of the
  -- CASE-in-WHERE statement scans all of hive_votes. The values also fold the $5 CASE to the one
  -- jsonb_build_object of the presentation mode, so the planner removes the author, permlink and
  -- reputation LEFT JOINs that mode does not output.
  EXECUTE $query$
    SELECT jsonb_agg(r.vote) -- list_votes
      FROM (
      SELECT
        ( CASE
            WHEN $5 = 'condenser_api' THEN jsonb_build_object(
              'percent', v.vote_percent::TEXT,
              'reputation', ha_v.reputation,
              'rshares', hivemind_app.json_stringify_numeric(v.rshares),
              'voter', ha_v.name
            )
            WHEN $5 = 'database_api' THEN jsonb_build_object(
              'voter', ha_v.name,
              'author', ha_a.name,
              'permlink', hpd.permlink,
              'weight', hivemind_app.json_stringify_numeric(v.weight),
              'rshares', hivemind_app.json_stringify_numeric(v.rshares),
              'vote_percent', v.vote_percent,
              'last_update', hivemind_postgrest_utilities.json_date(v.last_update),
              'num_changes', v.num_changes
            )
            WHEN $5 = 'bridge_api' THEN jsonb_build_object(
              'rshares', hivemind_app.json_stringify_numeric(v.rshares),
              'voter', ha_v.name
            )
            WHEN $5 = 'active_votes' THEN jsonb_build_object(
              'percent', v.vote_percent,
              'reputation', ha_v.reputation,
              'rshares', hivemind_app.json_stringify_numeric(v.rshares),
              'voter', ha_v.name,
              'time', hivemind_postgrest_utilities.json_date(v.last_update),
              'weight', hivemind_app.json_stringify_numeric(v.weight)
            )
            WHEN $5 = 'bridge_list_votes' THEN jsonb_build_object(
              'voter', ha_v.name,
              'rshares', hivemind_app.json_stringify_numeric(v.rshares),
              'percent', v.vote_percent,
              'weight', hivemind_app.json_stringify_numeric(v.weight),
              'time', hivemind_postgrest_utilities.json_date(v.last_update),
              'reputation', hivemind_postgrest_utilities.rep_log10(ha_v.reputation)
            )
          END
        ) AS vote
      -- hive_votes_view joined inline: by_voter_comment pages on hive_votes.author_id, which the view does not expose
      FROM
        hivemind_app.hive_votes AS v
        JOIN hivemind_app.hive_accounts_view ha_v ON ha_v.id = v.voter_id
        -- LEFT, so the planner can remove them: hive_votes_fk3/fk4 guarantee the match
        LEFT JOIN hivemind_app.hive_accounts ha_a ON ha_a.id = v.author_id
        LEFT JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = v.permlink_id
      WHERE
      ( CASE
          WHEN $4 = 'get_votes_for_posts' THEN v.post_id = $2
          WHEN $4 = 'database_list_by_comment_voter' THEN (v.post_id = $2 AND v.voter_id >= $6)
          -- (author_id, permlink_id) order lets hive_votes_voter_id_author_id_permlink_id_uk bound the scan
          WHEN $4 = 'database_list_by_voter_comment' THEN (v.voter_id = $6 AND (v.author_id, v.permlink_id) >= ($7, $8))
          WHEN $4 = 'bridge_list_by_comment_voter_after' THEN (v.post_id = $2 AND v.voter_id > $6)
          -- newest first by (last_update, id); the last_update bound lets hive_votes_voter_id_last_update_idx bound the scan
          WHEN $4 = 'list_by_voter_last_update_before' THEN (v.voter_id = $6 AND v.last_update <= $9 AND (v.last_update < $9 OR v.id < $10))
        END
      )
      AND ($1 = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = $1 AND muted_id = v.voter_id))
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
      ),
      ( CASE
          WHEN $4 = 'list_by_voter_last_update_before' THEN v.last_update
        END
      ) DESC,
      ( CASE
          WHEN $4 = 'list_by_voter_last_update_before' THEN v.id
        END
      ) DESC
      LIMIT $3
    ) r
  $query$
  INTO _result
  USING _observer_id, _post_id, _limit, _case, _presentation_mode, _voter_id, _start_author_id, _start_permlink_id, _before_last_update, _before_vote_id;

  RETURN COALESCE(_result, '[]'::jsonb);
END;
$function$
;
