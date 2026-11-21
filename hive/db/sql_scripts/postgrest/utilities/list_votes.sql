DROP TYPE IF EXISTS hivemind_postgrest_utilities.vote_presentation CASCADE;
CREATE TYPE hivemind_postgrest_utilities.vote_presentation AS ENUM( 'database_api', 'condenser_api', 'bridge_api', 'active_votes', 'bridge_list_votes');

DROP TYPE IF EXISTS hivemind_postgrest_utilities.list_votes_case CASCADE;
CREATE TYPE hivemind_postgrest_utilities.list_votes_case AS ENUM( 'get_votes_for_posts', 'database_list_by_comment_voter', 'database_list_by_voter_comment', 'bridge_list_by_comment_voter_after', 'list_by_voter_last_update_before');

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.list_votes;
CREATE FUNCTION hivemind_postgrest_utilities.list_votes(IN _observer_id INTEGER, IN _post_id INT, IN _limit INT, IN _case hivemind_postgrest_utilities.list_votes_case, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation, IN _voter_id INT DEFAULT NULL, IN _start_author_id INT DEFAULT NULL, IN _start_permlink_id INT DEFAULT NULL, IN _before_last_update TIMESTAMP DEFAULT NULL, IN _before_vote_id BIGINT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
-- Each statement's generic plan costs more than its custom plans, whose folded parameters drop the observer filter
-- and know the LIMIT, so the plan cache would otherwise re-plan every call.
SET plan_cache_mode = force_generic_plan
AS
$function$
DECLARE
_result JSONB;
_votes hivemind_app.hive_votes[];
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

  -- One static statement per case, so each cached generic plan still bounds its hive_votes scan by that case's index.
  -- The chosen rows, in order, then go through the one projection of their presentation mode.
  IF _case = 'get_votes_for_posts' THEN
    SELECT array_agg(s.v) INTO _votes FROM (
      SELECT v FROM hivemind_app.hive_votes v
      WHERE v.post_id = _post_id
        AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = v.voter_id))
      ORDER BY v.voter_id
      LIMIT _limit
    ) s;
  ELSIF _case = 'database_list_by_comment_voter' THEN
    SELECT array_agg(s.v) INTO _votes FROM (
      SELECT v FROM hivemind_app.hive_votes v
      WHERE v.post_id = _post_id AND v.voter_id >= _voter_id
        AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = v.voter_id))
      ORDER BY v.voter_id
      LIMIT _limit
    ) s;
  ELSIF _case = 'database_list_by_voter_comment' THEN
    -- (author_id, permlink_id) order lets hive_votes_voter_id_author_id_permlink_id_uk bound the scan
    SELECT array_agg(s.v) INTO _votes FROM (
      SELECT v FROM hivemind_app.hive_votes v
      WHERE v.voter_id = _voter_id AND (v.author_id, v.permlink_id) >= (_start_author_id, _start_permlink_id)
        AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = v.voter_id))
      ORDER BY v.author_id, v.permlink_id
      LIMIT _limit
    ) s;
  ELSIF _case = 'bridge_list_by_comment_voter_after' THEN
    SELECT array_agg(s.v) INTO _votes FROM (
      SELECT v FROM hivemind_app.hive_votes v
      WHERE v.post_id = _post_id AND v.voter_id > _voter_id
        AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = v.voter_id))
      ORDER BY v.voter_id
      LIMIT _limit
    ) s;
  ELSIF _case = 'list_by_voter_last_update_before' THEN
    -- newest first by (last_update, id); the last_update bound lets hive_votes_voter_id_last_update_idx bound the scan
    SELECT array_agg(s.v) INTO _votes FROM (
      SELECT v FROM hivemind_app.hive_votes v
      WHERE v.voter_id = _voter_id AND v.last_update <= _before_last_update AND (v.last_update < _before_last_update OR v.id < _before_vote_id)
        AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = v.voter_id))
      ORDER BY v.last_update DESC, v.id DESC
      LIMIT _limit
    ) s;
  END IF;

  IF _votes IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  -- Generic plans do not fold the presentation CASE, so the reputation join (through hive_accounts_view) is in a
  -- statement of its own, and database_api's author and permlink are scalar subqueries that run only in its branch.
  IF _presentation_mode IN ('condenser_api', 'active_votes', 'bridge_list_votes') THEN
    SELECT jsonb_agg(
      ( CASE
          WHEN _presentation_mode = 'condenser_api' THEN jsonb_build_object(
            'percent', v.vote_percent::TEXT,
            'reputation', ha_v.reputation,
            'rshares', hivemind_app.json_stringify_numeric(v.rshares),
            'voter', ha_v.name
          )
          WHEN _presentation_mode = 'active_votes' THEN jsonb_build_object(
            'percent', v.vote_percent,
            'reputation', ha_v.reputation,
            'rshares', hivemind_app.json_stringify_numeric(v.rshares),
            'voter', ha_v.name,
            'time', hivemind_postgrest_utilities.json_date(v.last_update),
            'weight', hivemind_app.json_stringify_numeric(v.weight)
          )
          WHEN _presentation_mode = 'bridge_list_votes' THEN jsonb_build_object(
            'voter', ha_v.name,
            'rshares', hivemind_app.json_stringify_numeric(v.rshares),
            'percent', v.vote_percent,
            'weight', hivemind_app.json_stringify_numeric(v.weight),
            'time', hivemind_postgrest_utilities.json_date(v.last_update),
            'reputation', hivemind_postgrest_utilities.rep_log10(ha_v.reputation)
          )
        END
      ) ORDER BY v.ordinality
    )
    INTO _result
    FROM unnest(_votes) WITH ORDINALITY AS v
    JOIN hivemind_app.hive_accounts_view ha_v ON ha_v.id = v.voter_id;
  ELSE
    SELECT jsonb_agg(
      ( CASE
          WHEN _presentation_mode = 'database_api' THEN jsonb_build_object(
            'voter', ha_v.name,
            'author', (SELECT ha_a.name FROM hivemind_app.hive_accounts ha_a WHERE ha_a.id = v.author_id),
            'permlink', (SELECT hpd.permlink FROM hivemind_app.hive_permlink_data hpd WHERE hpd.id = v.permlink_id),
            'weight', hivemind_app.json_stringify_numeric(v.weight),
            'rshares', hivemind_app.json_stringify_numeric(v.rshares),
            'vote_percent', v.vote_percent,
            'last_update', hivemind_postgrest_utilities.json_date(v.last_update),
            'num_changes', v.num_changes
          )
          WHEN _presentation_mode = 'bridge_api' THEN jsonb_build_object(
            'rshares', hivemind_app.json_stringify_numeric(v.rshares),
            'voter', ha_v.name
          )
        END
      ) ORDER BY v.ordinality
    )
    INTO _result
    FROM unnest(_votes) WITH ORDINALITY AS v
    JOIN hivemind_app.hive_accounts ha_v ON ha_v.id = v.voter_id;
  END IF;

  RETURN COALESCE(_result, '[]'::jsonb);
END;
$function$
;
