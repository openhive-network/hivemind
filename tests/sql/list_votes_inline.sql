-- list_votes builds each vote's JSON inline, and json_stringify_numeric and json_date are
-- single-expression SQL functions the planner inlines. Checks, against copies of the
-- plpgsql versions they replaced (pg_temp.old_*):
--   - both helpers at their boundaries: ±9007199254740991 and one beyond, NULL, infinity,
--     9999-12-31 23:59:59, and that EXPLAIN VERBOSE shows them inlined;
--   - list_votes in every vote_presentation and list_votes_case, with and without an
--     observer who mutes two voters, on posts with 0, 3 and 1101 votes (cut at the limit),
--     with rshares and weights beyond the JSON safe-integer range.
-- Seeds its own accounts, posts and votes in a transaction it rolls back, so it runs on any
-- installed hivemind schema, including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/list_votes_inline.sql

\set ON_ERROR_STOP 1
BEGIN;

CREATE FUNCTION pg_temp.old_json_stringify_numeric(in n NUMERIC)
RETURNS JSONB
IMMUTABLE
LANGUAGE 'plpgsql'
AS $$
DECLARE
  __json_min_safe_integer NUMERIC := -9007199254740991;
  __json_max_safe_integer NUMERIC := 9007199254740991;
BEGIN
  RETURN (
    SELECT CASE
      WHEN n BETWEEN __json_min_safe_integer AND __json_max_safe_integer
        THEN
          to_jsonb(n::BIGINT)
      ELSE
          to_jsonb(n::TEXT)
    END
  );
END;
$$;

CREATE FUNCTION pg_temp.old_json_date(_date TIMESTAMP DEFAULT NULL)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _date IS NULL OR _date = '9999-12-31 23:59:59+00'::TIMESTAMP OR _date = 'infinity' THEN
      RETURN '1969-12-31T23:59:59';
  END IF;

  RETURN TO_CHAR(_date, 'YYYY-MM-DD') || 'T' || TO_CHAR(_date, 'HH24:MI:SS');

END;
$BODY$
;

CREATE FUNCTION pg_temp.old_apply_vote_presentation(IN _vote RECORD, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation)
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
      'rshares', pg_temp.old_json_stringify_numeric(_vote.rshares),
      'voter', _vote.voter
    );
  ELSIF _presentation_mode = 'database_api' THEN
    RETURN jsonb_build_object(
      'voter', _vote.voter,
      'author', _vote.author,
      'permlink', _vote.permlink,
      'weight', pg_temp.old_json_stringify_numeric(_vote.weight),
      'rshares', pg_temp.old_json_stringify_numeric(_vote.rshares),
      'vote_percent', _vote.percent,
      'last_update', pg_temp.old_json_date(to_timestamp(_vote.last_update::TEXT, 'YYYY-MM-DD"T"HH24:MI:SS')::TIMESTAMP),
      'num_changes', _vote.num_changes
    );
  ELSIF _presentation_mode = 'bridge_api' THEN
    RETURN jsonb_build_object(
      'rshares', pg_temp.old_json_stringify_numeric(_vote.rshares),
      'voter', _vote.voter
    );
  ELSIF _presentation_mode = 'active_votes' THEN
    RETURN jsonb_build_object(
      'percent', _vote.percent,
      'reputation', _vote.reputation,
      'rshares', pg_temp.old_json_stringify_numeric(_vote.rshares),
      'voter', _vote.voter,
      'time', pg_temp.old_json_date(to_timestamp(_vote.last_update::TEXT, 'YYYY-MM-DD"T"HH24:MI:SS')::TIMESTAMP),
      'weight', pg_temp.old_json_stringify_numeric(_vote.weight)
    )::jsonb;
  ELSIF _presentation_mode = 'bridge_list_votes' THEN
    RETURN jsonb_build_object(
      'voter', _vote.voter,
      'rshares', pg_temp.old_json_stringify_numeric(_vote.rshares),
      'percent', _vote.percent,
      'weight', pg_temp.old_json_stringify_numeric(_vote.weight),
      'time', pg_temp.old_json_date(to_timestamp(_vote.last_update::TEXT, 'YYYY-MM-DD"T"HH24:MI:SS')::TIMESTAMP),
      'reputation', hivemind_postgrest_utilities.rep_log10(_vote.reputation)
    );
  ELSE
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('create_votes_json_array - unspecified vote presentation mode');
  END IF;
END;
$function$
;

CREATE FUNCTION pg_temp.old_list_votes(IN _observer_id INTEGER, IN _post_id INT, IN _limit INT, IN _case hivemind_postgrest_utilities.list_votes_case, IN _presentation_mode hivemind_postgrest_utilities.vote_presentation, IN _voter_id INT DEFAULT NULL, IN _start_author_id INT DEFAULT NULL, IN _start_permlink_id INT DEFAULT NULL, IN _before_last_update TIMESTAMP DEFAULT NULL, IN _before_vote_id BIGINT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS
$function$
DECLARE
_result JSONB;
_with_reputation BOOLEAN := _presentation_mode NOT IN ('bridge_api', 'database_api');
BEGIN
  EXECUTE $query$
    SELECT jsonb_agg(
        pg_temp.old_apply_vote_presentation(r, $5)
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
      FROM
        hivemind_app.hive_votes AS v
        JOIN hivemind_app.hive_accounts_view ha_v ON ha_v.id = v.voter_id
        JOIN hivemind_app.hive_accounts ha_a ON ha_a.id = v.author_id
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = v.permlink_id
      WHERE
      ( CASE
          WHEN $4 = 'get_votes_for_posts' THEN v.post_id = $2
          WHEN $4 = 'database_list_by_comment_voter' THEN (v.post_id = $2 AND v.voter_id >= $6)
          WHEN $4 = 'database_list_by_voter_comment' THEN (v.voter_id = $6 AND (v.author_id, v.permlink_id) >= ($8, $9))
          WHEN $4 = 'bridge_list_by_comment_voter_after' THEN (v.post_id = $2 AND v.voter_id > $6)
          WHEN $4 = 'list_by_voter_last_update_before' THEN (v.voter_id = $6 AND v.last_update <= $10 AND (v.last_update < $10 OR v.id < $11))
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
  USING _observer_id, _post_id, _limit, _case, _presentation_mode, _voter_id, _with_reputation, _start_author_id, _start_permlink_id, _before_last_update, _before_vote_id;

  RETURN COALESCE(_result, '[]'::jsonb);
END;
$function$
;

-- the helpers
DO $$
DECLARE
  _n NUMERIC;
  _d TIMESTAMP;
  _plan TEXT;
BEGIN
  FOR _n IN SELECT unnest(ARRAY[0, 1, -1, 12.5, 9007199254740990, 9007199254740991, 9007199254740992, -9007199254740991, -9007199254740992,
                                12345678901234567890, 9223372036854775807, -9223372036854775808, 'NaN', NULL]::NUMERIC[]) LOOP
    IF hivemind_app.json_stringify_numeric(_n) IS DISTINCT FROM pg_temp.old_json_stringify_numeric(_n) THEN
      RAISE EXCEPTION 'json_stringify_numeric(%): % but the plpgsql version gives %', _n, hivemind_app.json_stringify_numeric(_n), pg_temp.old_json_stringify_numeric(_n);
    END IF;
  END LOOP;
  IF hivemind_app.json_stringify_numeric(9007199254740991) <> '9007199254740991'::JSONB
     OR hivemind_app.json_stringify_numeric(9007199254740992) <> '"9007199254740992"'::JSONB
     OR hivemind_app.json_stringify_numeric(-9007199254740991) <> '-9007199254740991'::JSONB
     OR hivemind_app.json_stringify_numeric(-9007199254740992) <> '"-9007199254740992"'::JSONB
     OR hivemind_app.json_stringify_numeric(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'json_stringify_numeric: wrong boundary values';
  END IF;

  FOR _d IN SELECT unnest(ARRAY['2016-06-02 01:02:03', '1970-01-01 00:00:00', '1969-12-31 23:59:59', '2016-06-02 01:02:03.75',
                                '9999-12-31 23:59:58', '9999-12-31 23:59:59', 'infinity', '-infinity', NULL]::TIMESTAMP[]) LOOP
    IF hivemind_postgrest_utilities.json_date(_d) IS DISTINCT FROM pg_temp.old_json_date(_d) THEN
      RAISE EXCEPTION 'json_date(%): % but the plpgsql version gives %', _d, hivemind_postgrest_utilities.json_date(_d), pg_temp.old_json_date(_d);
    END IF;
  END LOOP;
  IF hivemind_postgrest_utilities.json_date() <> '1969-12-31T23:59:59'
     OR hivemind_postgrest_utilities.json_date('infinity') <> '1969-12-31T23:59:59'
     OR hivemind_postgrest_utilities.json_date('9999-12-31 23:59:59') <> '1969-12-31T23:59:59'
     OR hivemind_postgrest_utilities.json_date('2016-06-02 01:02:03') <> '2016-06-02T01:02:03' THEN
    RAISE EXCEPTION 'json_date: wrong boundary values';
  END IF;

  FOR _plan IN EXECUTE 'EXPLAIN (VERBOSE, COSTS OFF) SELECT hivemind_app.json_stringify_numeric(v.rshares), hivemind_app.json_stringify_numeric(v.weight), hivemind_postgrest_utilities.json_date(v.last_update) FROM hivemind_app.hive_votes v' LOOP
    IF _plan ~ 'json_stringify_numeric|json_date' THEN
      RAISE EXCEPTION 'a helper is not inlined: %', _plan;
    END IF;
  END LOOP;
END
$$;

-- vs-0001 .. vs-1100 vote on the big post; vs-0001 .. vs-0003 also on the small one, and
-- vs-0001 on the third; vs-observer mutes vs-0002 and vs-0003
INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + i, 'vs-' || lpad(i::TEXT, 4, '0'), '2016-06-01' FROM generate_series(1, 1100) i ORDER BY i;
INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['vs-author', 'vs-observer']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('vs-big'), ('vs-small'), ('vs-third'), ('vs-empty');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('vs-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'vs-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = p.permlink),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'vs-cat'),
  '2016-06-01', 0, 1, 1
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, permlink
      FROM unnest(ARRAY['vs-big', 'vs-small', 'vs-third', 'vs-empty']) WITH ORDINALITY AS u(permlink, n) ORDER BY n) p;

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num)
SELECT hp.id, ha.id, hp.author_id, hp.permlink_id,
  (CASE WHEN ha.name = 'vs-0004' THEN 12345678901234567890 ELSE i * 7 END),
  (CASE ha.name
     WHEN 'vs-0001' THEN 9007199254740992 WHEN 'vs-0002' THEN -9007199254740992
     WHEN 'vs-0003' THEN 9007199254740991 WHEN 'vs-0005' THEN -9223372036854775808
     ELSE i * 1000 - 300000 END),
  (CASE WHEN i % 3 = 0 THEN -10000 ELSE i END),
  (CASE WHEN ha.name = 'vs-0006' THEN '1970-01-01 00:00:00'::TIMESTAMP ELSE '2016-06-02'::TIMESTAMP + i * INTERVAL '1 minute' + hpd.permlink_n * INTERVAL '1 day' END),
  i % 4, 1
FROM (SELECT ha.*, substr(ha.name, 4)::INT AS i FROM hivemind_app.hive_accounts ha WHERE ha.name ~ '^vs-[0-9]{4}$') ha
CROSS JOIN LATERAL (VALUES ('vs-big', 0), ('vs-small', 1), ('vs-third', 2)) AS hpd(permlink, permlink_n)
JOIN hivemind_app.hive_permlink_data pd ON pd.permlink = hpd.permlink
JOIN hivemind_app.hive_posts hp ON hp.permlink_id = pd.id
WHERE hpd.permlink = 'vs-big' OR (hpd.permlink = 'vs-small' AND ha.i <= 3) OR (hpd.permlink = 'vs-third' AND ha.i = 1);

INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'vs-observer' AND m.name IN ('vs-0002', 'vs-0003');

DO $$
DECLARE
  _observer INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'vs-observer');
  _v1 INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'vs-0001');
  _v2 INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'vs-0002');
  _author INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'vs-author');
  _big INT;
  _small INT;
  _third INT;
  _empty INT;
  _small_permlink INT := (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'vs-small');
  _small_update TIMESTAMP;
  _small_vote BIGINT;
  _mode hivemind_postgrest_utilities.vote_presentation;
  _observer_id INT;
  _post INT;
  _limit INT;
  _calls INT := 0;
  _old JSONB;
  _new JSONB;
  _seen JSONB := '{}';
BEGIN
  SELECT hp.id INTO _big FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id WHERE pd.permlink = 'vs-big';
  SELECT hp.id INTO _small FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id WHERE pd.permlink = 'vs-small';
  SELECT hp.id INTO _third FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id WHERE pd.permlink = 'vs-third';
  SELECT hp.id INTO _empty FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id WHERE pd.permlink = 'vs-empty';
  SELECT last_update, id INTO _small_update, _small_vote FROM hivemind_app.hive_votes WHERE post_id = _small AND voter_id = _v1;

  FOR _mode IN SELECT unnest(enum_range(NULL::hivemind_postgrest_utilities.vote_presentation)) LOOP
    FOREACH _observer_id IN ARRAY ARRAY[-1, _observer] LOOP
      FOREACH _limit IN ARRAY ARRAY[1000, 2] LOOP
        FOREACH _post IN ARRAY ARRAY[_big, _small, _third, _empty] LOOP
          _old = pg_temp.old_list_votes(_observer_id, _post, _limit, 'get_votes_for_posts', _mode);
          _new = hivemind_postgrest_utilities.list_votes(_observer_id, _post, _limit, 'get_votes_for_posts', _mode);
          IF _new IS DISTINCT FROM _old THEN
            RAISE EXCEPTION 'get_votes_for_posts % post % observer % limit %: % <> %', _mode, _post, _observer_id, _limit, left(_new::TEXT, 400), left(_old::TEXT, 400);
          END IF;
          _seen = _seen || jsonb_build_object(format('%s/%s/%s/%s', _mode, _post = _big, _observer_id, _limit), jsonb_array_length(_new));

          _old = pg_temp.old_list_votes(_observer_id, _post, _limit, 'database_list_by_comment_voter', _mode, _v2);
          _new = hivemind_postgrest_utilities.list_votes(_observer_id, _post, _limit, 'database_list_by_comment_voter', _mode, _v2);
          IF _new IS DISTINCT FROM _old THEN
            RAISE EXCEPTION 'database_list_by_comment_voter % post %: % <> %', _mode, _post, left(_new::TEXT, 400), left(_old::TEXT, 400);
          END IF;

          _old = pg_temp.old_list_votes(_observer_id, _post, _limit, 'bridge_list_by_comment_voter_after', _mode, _v1);
          _new = hivemind_postgrest_utilities.list_votes(_observer_id, _post, _limit, 'bridge_list_by_comment_voter_after', _mode, _v1);
          IF _new IS DISTINCT FROM _old THEN
            RAISE EXCEPTION 'bridge_list_by_comment_voter_after % post %: % <> %', _mode, _post, left(_new::TEXT, 400), left(_old::TEXT, 400);
          END IF;
          _calls = _calls + 3;
        END LOOP;

        _old = pg_temp.old_list_votes(_observer_id, NULL, _limit, 'database_list_by_voter_comment', _mode, _v1, _author, _small_permlink);
        _new = hivemind_postgrest_utilities.list_votes(_observer_id, NULL, _limit, 'database_list_by_voter_comment', _mode, _v1, _author, _small_permlink);
        IF _new IS DISTINCT FROM _old OR jsonb_array_length(_new) <> LEAST(_limit, 2) THEN
          RAISE EXCEPTION 'database_list_by_voter_comment %: % <> %', _mode, _new, _old;
        END IF;

        _old = pg_temp.old_list_votes(_observer_id, NULL, _limit, 'list_by_voter_last_update_before', _mode, _v1, NULL, NULL, _small_update, _small_vote);
        _new = hivemind_postgrest_utilities.list_votes(_observer_id, NULL, _limit, 'list_by_voter_last_update_before', _mode, _v1, NULL, NULL, _small_update, _small_vote);
        IF _new IS DISTINCT FROM _old OR jsonb_array_length(_new) <> LEAST(_limit, 1) THEN
          RAISE EXCEPTION 'list_by_voter_last_update_before %: % <> %', _mode, _new, _old;
        END IF;
        _calls = _calls + 2;
      END LOOP;
    END LOOP;
  END LOOP;

  -- the comparisons above saw the limit, the muted voters and the out-of-range values
  IF (_seen->>'bridge_api/true/-1/1000')::INT <> 1000 OR (_seen->>'bridge_api/true/-1/2')::INT <> 2 THEN
    RAISE EXCEPTION 'the big post: expected 1000 and 2 votes, got %', _seen;
  END IF;
  IF hivemind_postgrest_utilities.list_votes(-1, _small, 1000, 'get_votes_for_posts', 'bridge_api')
       <> '[{"voter": "vs-0001", "rshares": "9007199254740992"}, {"voter": "vs-0002", "rshares": "-9007199254740992"}, {"voter": "vs-0003", "rshares": 9007199254740991}]'::JSONB
     OR hivemind_postgrest_utilities.list_votes(_observer, _small, 1000, 'get_votes_for_posts', 'bridge_api')
       <> '[{"voter": "vs-0001", "rshares": "9007199254740992"}]'::JSONB THEN
    RAISE EXCEPTION 'the small post: wrong votes for no observer or the muting observer';
  END IF;
  IF hivemind_postgrest_utilities.list_votes(-1, _empty, 1000, 'get_votes_for_posts', 'active_votes') <> '[]'::JSONB THEN
    RAISE EXCEPTION 'the empty post: expected []';
  END IF;
  IF NOT hivemind_postgrest_utilities.list_votes(-1, _small, 1000, 'get_votes_for_posts', 'database_api')
       @> '[{"voter": "vs-0001", "author": "vs-author", "permlink": "vs-small"}]'::JSONB THEN
    RAISE EXCEPTION 'database_api: expected the author and permlink';
  END IF;
  RAISE NOTICE 'list_votes: % calls equal to the plpgsql version', _calls;
END
$$;

ROLLBACK;
