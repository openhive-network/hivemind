-- list_votes runs its statements as cached generic plans (SET plan_cache_mode =
-- force_generic_plan). For every list_votes_case in every vote_presentation, with and
-- without an observer who mutes a voter, this checks through the transaction's own
-- scan counters (pg_stat_get_xact_*) that:
--   - the case reads its bounded index, hive_votes_post_id_voter_id_idx,
--     hive_votes_voter_id_author_id_permlink_id_uk or hive_votes_voter_id_last_update_idx,
--     returns from hive_votes' indexes fewer tuples than half way from the post's or the
--     voter's votes to a walk of the whole table, and never scans hive_votes sequentially
--     (index scans also return the dead entries earlier rolled-back tests left under
--     the reused account ids, so the bound is no tighter);
--   - bridge_api and database_api read no account_reputations, and bridge_api reads no
--     hive_permlink_data and no hive_accounts beyond one probe per vote (the voter's);
--   - database_api runs its author and permlink lookups, one per vote;
--   - the formats that output reputation do read account_reputations, so the counters
--     see that access when it happens.
-- Seeds its own accounts, posts and votes in a transaction it rolls back, so it runs on
-- any installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/list_votes_generic_plans.sql
--
-- lp-0001 .. lp-1100 vote on lp-big and lp-third; lp-0001 also on lp-small; lp-observer
-- mutes lp-0002.

\set ON_ERROR_STOP 1
BEGIN;

-- sequential scans of the table plus scans of each of its indexes, in this transaction
CREATE FUNCTION pg_temp.scans(_rel REGCLASS)
RETURNS BIGINT
LANGUAGE sql
AS $$
  SELECT pg_stat_get_xact_numscans(_rel) + COALESCE((SELECT sum(pg_stat_get_xact_numscans(i.indexrelid)) FROM pg_index i WHERE i.indrelid = _rel), 0)::BIGINT
$$;

CREATE FUNCTION pg_temp.index_tuples(_rel REGCLASS)
RETURNS BIGINT
LANGUAGE sql
AS $$
  SELECT COALESCE(sum(pg_stat_get_xact_tuples_returned(i.indexrelid)), 0)::BIGINT FROM pg_index i WHERE i.indrelid = _rel
$$;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + i, 'lp-' || lpad(i::TEXT, 4, '0'), '2016-06-01' FROM generate_series(1, 1100) i ORDER BY i;
INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['lp-author', 'lp-observer']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink) VALUES ('lp-big'), ('lp-small'), ('lp-third');
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('lp-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'lp-author'),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = p.permlink),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'lp-cat'),
  '2016-06-01', 0, 1, 1
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, permlink
      FROM unnest(ARRAY['lp-big', 'lp-small', 'lp-third']) WITH ORDINALITY AS u(permlink, n) ORDER BY n) p;

INSERT INTO hivemind_app.hive_votes (post_id, voter_id, author_id, permlink_id, weight, rshares, vote_percent, last_update, num_changes, block_num)
SELECT hp.id, ha.id, hp.author_id, hp.permlink_id, i * 7, i * 1000, i, '2016-06-02'::TIMESTAMP + i * INTERVAL '1 minute' + hpd.permlink_n * INTERVAL '1 day', 0, 1
FROM (SELECT ha.*, substr(ha.name, 4)::INT AS i FROM hivemind_app.hive_accounts ha WHERE ha.name ~ '^lp-[0-9]{4}$') ha
CROSS JOIN LATERAL (VALUES ('lp-big', 0), ('lp-small', 1), ('lp-third', 2)) AS hpd(permlink, permlink_n)
JOIN hivemind_app.hive_permlink_data pd ON pd.permlink = hpd.permlink
JOIN hivemind_app.hive_posts hp ON hp.permlink_id = pd.id
WHERE hpd.permlink <> 'lp-small' OR ha.i = 1;

INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'lp-observer' AND m.name = 'lp-0002';

ANALYZE hivemind_app.hive_accounts, hivemind_app.hive_permlink_data, hivemind_app.hive_votes;

DO $$
DECLARE
  _observer INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'lp-observer');
  _v1 INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'lp-0001');
  _v2 INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'lp-0002');
  _author INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'lp-author');
  _big INT := (SELECT hp.id FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id WHERE pd.permlink = 'lp-big');
  _small INT := (SELECT hp.id FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data pd ON pd.id = hp.permlink_id WHERE pd.permlink = 'lp-small');
  _small_permlink INT := (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'lp-small');
  _big_votes BIGINT := (SELECT count(*) FROM hivemind_app.hive_votes WHERE post_id = _big);
  _v1_votes BIGINT := (SELECT count(*) FROM hivemind_app.hive_votes WHERE voter_id = _v1);
  _all_votes BIGINT := (SELECT reltuples FROM pg_class WHERE oid = 'hivemind_app.hive_votes'::regclass);
  _small_update TIMESTAMP;
  _small_vote BIGINT;
  _reputations REGCLASS;
  _case hivemind_postgrest_utilities.list_votes_case;
  _mode hivemind_postgrest_utilities.vote_presentation;
  _observer_id INT;
  _index REGCLASS;
  _bound BIGINT;
  _what TEXT;
  _r JSONB;
  _n INT;
  _calls INT := 0;
  _seq BIGINT;
  _index_scans BIGINT;
  _tuples BIGINT;
  _reputation_scans BIGINT;
  _account_scans BIGINT;
  _permlink_scans BIGINT;
BEGIN
  SELECT last_update, id INTO _small_update, _small_vote FROM hivemind_app.hive_votes WHERE post_id = _small AND voter_id = _v1;

  -- the reputation table hive_accounts_view joins, wherever reputation_tracker is installed
  SELECT DISTINCT d.refobjid INTO _reputations
  FROM pg_rewrite rw
  JOIN pg_depend d ON d.classid = 'pg_rewrite'::regclass AND d.objid = rw.oid AND d.refclassid = 'pg_class'::regclass
  JOIN pg_class c ON c.oid = d.refobjid
  WHERE rw.ev_class = 'hivemind_app.hive_accounts_view'::regclass AND c.relname = 'account_reputations';
  IF _reputations IS NULL THEN
    RAISE EXCEPTION 'setup: hive_accounts_view joins no account_reputations, so its access cannot be counted';
  END IF;
  IF _big_votes < 1100 OR _v1_votes < 3 OR _all_votes < 2201 THEN
    RAISE EXCEPTION 'setup: lp-big has % votes, lp-0001 % and hive_votes %, expected 1100, 3 and 2201', _big_votes, _v1_votes, _all_votes;
  END IF;

  FOR _case IN SELECT unnest(enum_range(NULL::hivemind_postgrest_utilities.list_votes_case)) LOOP
    _index = CASE _case
      WHEN 'database_list_by_voter_comment' THEN 'hivemind_app.hive_votes_voter_id_author_id_permlink_id_uk'
      WHEN 'list_by_voter_last_update_before' THEN 'hivemind_app.hive_votes_voter_id_last_update_idx'
      ELSE 'hivemind_app.hive_votes_post_id_voter_id_idx'
    END::regclass;
    _bound = CASE WHEN _case IN ('database_list_by_voter_comment', 'list_by_voter_last_update_before') THEN _v1_votes ELSE _big_votes END;
    _bound = _bound + (_all_votes - _bound) / 2;

    FOR _mode IN SELECT unnest(enum_range(NULL::hivemind_postgrest_utilities.vote_presentation)) LOOP
      FOREACH _observer_id IN ARRAY ARRAY[-1, _observer] LOOP
        _what = format('%s %s observer %s', _case, _mode, _observer_id);
        _seq = pg_stat_get_xact_numscans('hivemind_app.hive_votes'::regclass);
        _index_scans = pg_stat_get_xact_numscans(_index);
        _tuples = pg_temp.index_tuples('hivemind_app.hive_votes'::regclass);
        _reputation_scans = pg_temp.scans(_reputations);
        _account_scans = pg_temp.scans('hivemind_app.hive_accounts'::regclass);
        _permlink_scans = pg_temp.scans('hivemind_app.hive_permlink_data'::regclass);

        _r = CASE _case
          WHEN 'get_votes_for_posts' THEN hivemind_postgrest_utilities.list_votes(_observer_id, _big, 50, _case, _mode)
          WHEN 'database_list_by_comment_voter' THEN hivemind_postgrest_utilities.list_votes(_observer_id, _big, 50, _case, _mode, _v2)
          WHEN 'bridge_list_by_comment_voter_after' THEN hivemind_postgrest_utilities.list_votes(_observer_id, _big, 50, _case, _mode, _v1)
          WHEN 'database_list_by_voter_comment' THEN hivemind_postgrest_utilities.list_votes(_observer_id, NULL, 50, _case, _mode, _v1, _author, _small_permlink)
          WHEN 'list_by_voter_last_update_before' THEN hivemind_postgrest_utilities.list_votes(_observer_id, NULL, 50, _case, _mode, _v1, NULL, NULL, _small_update, _small_vote)
        END;

        _seq = pg_stat_get_xact_numscans('hivemind_app.hive_votes'::regclass) - _seq;
        _index_scans = pg_stat_get_xact_numscans(_index) - _index_scans;
        _tuples = pg_temp.index_tuples('hivemind_app.hive_votes'::regclass) - _tuples;
        _reputation_scans = pg_temp.scans(_reputations) - _reputation_scans;
        _account_scans = pg_temp.scans('hivemind_app.hive_accounts'::regclass) - _account_scans;
        _permlink_scans = pg_temp.scans('hivemind_app.hive_permlink_data'::regclass) - _permlink_scans;
        _n = jsonb_array_length(_r);
        _calls = _calls + 1;

        IF _n <> (CASE _case WHEN 'database_list_by_voter_comment' THEN 2 WHEN 'list_by_voter_last_update_before' THEN 1 ELSE 50 END) THEN
          RAISE EXCEPTION '%: % votes: %', _what, _n, left(_r::TEXT, 400);
        END IF;
        IF _seq <> 0 THEN
          RAISE EXCEPTION '%: % sequential scans of hive_votes, expected none', _what, _seq;
        END IF;
        IF _index_scans = 0 THEN
          RAISE EXCEPTION '%: never scanned %', _what, _index;
        END IF;
        IF _tuples >= _bound THEN
          RAISE EXCEPTION '%: % tuples from hive_votes indexes, at least % (half way to the % rows of hive_votes) though the case''s index bound selects far fewer', _what, _tuples, _bound, _all_votes;
        END IF;

        IF _mode IN ('bridge_api', 'database_api') THEN
          IF _reputation_scans <> 0 THEN
            RAISE EXCEPTION '%: % scans of %, which this format does not output', _what, _reputation_scans, _reputations;
          END IF;
        ELSIF _reputation_scans = 0 THEN
          RAISE EXCEPTION '%: never read %, though this format outputs reputation', _what, _reputations;
        END IF;

        IF _mode = 'database_api' THEN
          IF _permlink_scans < _n OR _account_scans < _n + 1 THEN
            RAISE EXCEPTION '%: % hive_permlink_data and % hive_accounts scans for % votes, expected a permlink and an author lookup per vote and the voters', _what, _permlink_scans, _account_scans, _n;
          END IF;
        ELSIF _permlink_scans <> 0 THEN
          RAISE EXCEPTION '%: % scans of hive_permlink_data, which this format does not output', _what, _permlink_scans;
        END IF;
        IF _mode = 'bridge_api' AND _account_scans > _n THEN
          RAISE EXCEPTION '%: % hive_accounts scans for % votes, more than the voters'' probes', _what, _account_scans, _n;
        END IF;
      END LOOP;
    END LOOP;
  END LOOP;
  RAISE NOTICE 'list_votes: % calls on bounded generic plans', _calls;
END
$$;

ROLLBACK;
