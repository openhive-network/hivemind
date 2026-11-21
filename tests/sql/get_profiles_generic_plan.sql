-- get_profiles reads its accounts through get_accounts_info, whose lookup runs as a cached
-- generic plan (SET plan_cache_mode = force_generic_plan). Over more than five calls in one
-- session, with and without an observer who follows one account and mutes another, this checks
-- that:
--   - get_accounts_info carries the setting and get_profiles none of its own;
--   - every call answers exactly what the body before the helper answers, installed below as
--     pg_temp.old_get_profiles, including the error for a missing account;
--   - the lookup keeps its shape: hive_accounts by hive_accounts_ux1, and one probe each into
--     hive_posts and hive_votes for an account's latest post and vote, so no sequential scan of
--     those tables and fewer index tuples than the accounts' posts and votes.
-- Seeds its own accounts, posts and votes in a transaction it rolls back, so it runs on any
-- installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/get_profiles_generic_plan.sql
--
-- gpr-author writes 50 posts; gpr-0001 .. gpr-0003 vote on each. gpr-observer follows gpr-0001
-- and mutes gpr-0002.

\set ON_ERROR_STOP 1
BEGIN;

CREATE FUNCTION pg_temp.index_tuples(_rel REGCLASS)
RETURNS BIGINT
LANGUAGE sql
AS $$
  SELECT COALESCE(sum(pg_stat_get_xact_tuples_returned(i.indexrelid)), 0)::BIGINT FROM pg_index i WHERE i.indrelid = _rel
$$;

-- get_profiles as it was before get_accounts_info
CREATE FUNCTION pg_temp.old_get_profiles(IN   _accounts JSONB, IN  _observer TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  _account_names TEXT[];
  _observer_id INT;
  _result JSONB;
  _found_accounts_amount INT;
  _accounts_amount INT;
  _found_accounts TEXT[];
  _missing_accounts JSONB;
BEGIN

    _accounts_amount = jsonb_array_length(_accounts);
    IF _accounts_amount > 1000 THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('accounts amount is greather than max allowed (1000)');
    END IF;

    _observer_id = hivemind_postgrest_utilities.find_account_id(
            hivemind_postgrest_utilities.valid_account(_observer, True),
            True);

    IF _accounts_amount = 0 THEN
        RETURN '[]'::jsonb;
    END IF;

    SELECT array_agg(value) INTO _account_names FROM jsonb_array_elements_text(_accounts);
    _account_names = hivemind_postgrest_utilities.valid_accounts(_account_names, false);

    SELECT jsonb_agg(jsonb_build_object(
            'id', row.id,
            'name', row.name,
            'created', hivemind_postgrest_utilities.json_date(row.created_at),
            'active', hivemind_postgrest_utilities.json_date(row.active_at),
            'post_count', row.post_count,
            'reputation', hivemind_postgrest_utilities.rep_log10(row.reputation),
            'blacklists', to_jsonb('{}'::INT[]),
            'stats', jsonb_build_object('rank', row.rank, 'following', row.following, 'followers', row.followers),
            'json_metadata', row.json_metadata,
            'posting_json_metadata', row.posting_json_metadata
        ) ORDER BY row.name ASC)
      FROM (SELECT * FROM hivemind_app.hive_accounts_info_view WHERE name = ANY(_account_names)) AS row
      INTO _result;


    SELECT array_agg(value#>>'{name}') INTO _found_accounts FROM jsonb_array_elements(_result);
    _found_accounts_amount = array_length(_found_accounts, 1);

    IF _accounts_amount <> _found_accounts_amount OR _found_accounts_amount IS NULL THEN
        IF _found_accounts_amount = 0 OR _found_accounts_amount IS NULL THEN
            SELECT jsonb_agg(jsonb_build_object(name, 'account does not exist'))
            INTO _missing_accounts
            FROM unnest(_account_names) name;
        ELSE
            SELECT array_agg(value#>>'{name}') INTO _found_accounts FROM jsonb_array_elements(_result);
            SELECT jsonb_agg(jsonb_build_object(name, 'account does not exist'))
            INTO _missing_accounts
            FROM (SELECT unnest(_account_names) as name EXCEPT SELECT unnest(_found_accounts)) missing;
        END IF;
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_missing_accounts::text);
    END IF;

    IF _observer_id IS NOT NULL AND _observer_id <> -1 THEN
        SELECT jsonb_agg(
                       jsonb_set(
                               account_row,
                               '{context}',
                               jsonb_build_object(
                                'followed', (SELECT EXISTS (SELECT NULL
                                  FROM hivemind_app.follows
                                  WHERE follower = _observer_id
                                  AND following = (account_row->>'id')::INT)),
                                'muted', (SELECT EXISTS (SELECT NULL
                                  FROM hivemind_app.muted
                                  WHERE follower = _observer_id
                                  AND following = (account_row->>'id')::INT)))
                           )
                   )
        FROM jsonb_array_elements(_result) account_row
        INTO _result;
    END IF;


    SELECT jsonb_agg(
                   jsonb_set(
                               account_row - 'json_metadata' - 'posting_json_metadata',
                               '{metadata}',
                               hivemind_postgrest_utilities.extract_profile_metadata(
                                           account_row->>'json_metadata',
                                           account_row->>'posting_json_metadata'
                                   )
                       )
               )
    FROM jsonb_array_elements(_result) account_row INTO _result;

    RETURN _result;
END
$function$
;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + i, 'gpr-' || lpad(i::TEXT, 4, '0'), '2016-06-01' FROM generate_series(1, 1100) i ORDER BY i;
INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['gpr-author', 'gpr-observer']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink) SELECT 'gpr-post-' || i FROM generate_series(1, 50) i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('gpr-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gpr-author'),
  p.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gpr-cat'),
  '2016-07-01'::TIMESTAMP + p.n * INTERVAL '1 hour', 0, 1, 1
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, pd.id AS permlink_id, substr(pd.permlink, 10)::INT AS n
      FROM hivemind_app.hive_permlink_data pd WHERE pd.permlink LIKE 'gpr-post-%' ORDER BY n) p;

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num)
SELECT hp.id, ha.id, hp.author_id, hp.permlink_id, 7, 1000, 100, hp.created_at + substr(ha.name, 5)::INT * INTERVAL '1 minute', 0, 1
FROM hivemind_app.hive_accounts ha
JOIN hivemind_app.hive_posts hp ON hp.author_id = (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gpr-author')
WHERE ha.name IN ('gpr-0001', 'gpr-0002', 'gpr-0003');

SELECT hivemind_app.insert_follows(ARRAY(
  SELECT ROW((SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gpr-observer'), ha.id, 1)::hivemind_app.follow_ids
  FROM hivemind_app.hive_accounts ha WHERE ha.name = 'gpr-0001'
));
INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'gpr-observer' AND m.name = 'gpr-0002';

ANALYZE hivemind_app.hive_accounts, hivemind_app.hive_posts, hivemind_app.hive_votes;

DO $$
DECLARE
  _config TEXT[] := (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_accounts_info(TEXT[])'::regprocedure);
  _accounts JSONB;
  _observer TEXT;
  _what TEXT;
  _r JSONB;
  _old JSONB;
  _error TEXT;
  _old_error TEXT;
  _calls INT := 0;
  _seq BIGINT;
  _ux1_scans BIGINT;
  _post_tuples BIGINT;
  _vote_tuples BIGINT;
  _held_posts BIGINT;
  _held_votes BIGINT;
BEGIN
  IF _config IS DISTINCT FROM ARRAY['plan_cache_mode=force_generic_plan'] THEN
    RAISE EXCEPTION 'get_accounts_info is configured %, expected only plan_cache_mode=force_generic_plan', _config;
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_profiles(JSONB, TEXT)'::regprocedure) IS NOT NULL THEN
    RAISE EXCEPTION 'get_profiles carries planner settings, which would hold for the functions it calls';
  END IF;

  FOR _rep IN 1..3 LOOP
    FOR _accounts IN SELECT * FROM unnest(ARRAY['["gpr-0001"]', '["gpr-0002", "gpr-author", "gpr-0001"]', '["gpr-1100"]']::JSONB[]) LOOP
      FOREACH _observer IN ARRAY ARRAY[NULL, 'gpr-observer'] LOOP
        _what = format('call %s accounts %s observer %s', _rep, _accounts, _observer);
        _seq = pg_stat_get_xact_numscans('hivemind_app.hive_accounts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_votes'::regclass);
        _ux1_scans = pg_stat_get_xact_numscans('hivemind_app.hive_accounts_ux1'::regclass);
        _post_tuples = pg_temp.index_tuples('hivemind_app.hive_posts'::regclass);
        _vote_tuples = pg_temp.index_tuples('hivemind_app.hive_votes'::regclass);

        _r = hivemind_postgrest_utilities.get_profiles(_accounts, _observer);

        _seq = pg_stat_get_xact_numscans('hivemind_app.hive_accounts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_votes'::regclass) - _seq;
        _ux1_scans = pg_stat_get_xact_numscans('hivemind_app.hive_accounts_ux1'::regclass) - _ux1_scans;
        _post_tuples = pg_temp.index_tuples('hivemind_app.hive_posts'::regclass) - _post_tuples;
        _vote_tuples = pg_temp.index_tuples('hivemind_app.hive_votes'::regclass) - _vote_tuples;
        _calls = _calls + 1;

        _old = pg_temp.old_get_profiles(_accounts, _observer);
        IF _r IS DISTINCT FROM _old THEN
          RAISE EXCEPTION '%: % differs from the pre-change answer %', _what, left(_r::TEXT, 600), left(_old::TEXT, 600);
        END IF;
        IF jsonb_array_length(_r) <> jsonb_array_length(_accounts) THEN
          RAISE EXCEPTION '%: % profiles: %', _what, jsonb_array_length(_r), left(_r::TEXT, 600);
        END IF;
        IF _accounts ? 'gpr-0001' AND NOT _r @> jsonb_build_array(jsonb_build_object('name', 'gpr-0001', 'active', '2016-07-03T02:01:00')) THEN
          RAISE EXCEPTION '%: gpr-0001 is not active at its latest vote: %', _what, left(_r::TEXT, 600);
        END IF;
        IF _accounts ? 'gpr-author' AND NOT _r @> jsonb_build_array(jsonb_build_object('name', 'gpr-author', 'active', '2016-07-03T02:00:00')) THEN
          RAISE EXCEPTION '%: gpr-author is not active at its latest post: %', _what, left(_r::TEXT, 600);
        END IF;
        IF _observer IS NOT NULL AND _accounts ? 'gpr-0001'
           AND NOT _r @> jsonb_build_array(jsonb_build_object('name', 'gpr-0001', 'context', jsonb_build_object('followed', true, 'muted', false))) THEN
          RAISE EXCEPTION '%: gpr-0001 is not followed by the observer: %', _what, left(_r::TEXT, 600);
        END IF;

        _held_posts = (SELECT count(*) FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
                       WHERE ha.name IN (SELECT jsonb_array_elements_text(_accounts)));
        _held_votes = (SELECT count(*) FROM hivemind_app.hive_votes hv JOIN hivemind_app.hive_accounts ha ON ha.id = hv.voter_id
                       WHERE ha.name IN (SELECT jsonb_array_elements_text(_accounts)));
        IF _seq <> 0 THEN
          RAISE EXCEPTION '%: % sequential scans of hive_accounts, hive_posts and hive_votes, expected none', _what, _seq;
        END IF;
        IF _ux1_scans = 0 THEN
          RAISE EXCEPTION '%: never scanned hive_accounts_ux1', _what;
        END IF;
        IF _held_posts > 1 AND _post_tuples >= _held_posts THEN
          RAISE EXCEPTION '%: % tuples from hive_posts indexes for accounts with % posts, expected one probe per account', _what, _post_tuples, _held_posts;
        END IF;
        IF _held_votes > 1 AND _vote_tuples >= _held_votes THEN
          RAISE EXCEPTION '%: % tuples from hive_votes indexes for accounts with % votes, expected one probe per account', _what, _vote_tuples, _held_votes;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;

  BEGIN
    PERFORM hivemind_postgrest_utilities.get_profiles('["gpr-0001", "gpr-nobody"]', 'gpr-observer');
  EXCEPTION WHEN raise_exception THEN
    _error = SQLERRM;
  END;
  BEGIN
    PERFORM pg_temp.old_get_profiles('["gpr-0001", "gpr-nobody"]', 'gpr-observer');
  EXCEPTION WHEN raise_exception THEN
    _old_error = SQLERRM;
  END;
  IF _error IS NULL OR _error IS DISTINCT FROM _old_error OR _error NOT LIKE '%gpr-nobody%' THEN
    RAISE EXCEPTION 'missing account: error %, before the change %', _error, _old_error;
  END IF;

  RAISE NOTICE 'get_profiles: % calls on the generic lookup, answers equal to the pre-change body', _calls;
END
$$;

ROLLBACK;
