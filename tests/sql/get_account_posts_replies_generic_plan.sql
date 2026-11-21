-- get_account_posts_by_replies reads its page of hive_replies through get_account_replies_page,
-- whose walk runs as a cached generic plan (SET plan_cache_mode = force_generic_plan). Over more
-- than five calls in one session (bridge and condenser, first page and continuation, with and
-- without an observer who mutes one replier), this checks that:
--   - get_account_replies_page carries only that setting, and get_account_posts_by_replies no
--     setting at all, so no join-method setting holds for the functions it calls;
--   - every call answers exactly what the body before the helper answers, installed below as
--     pg_temp.old_get_account_posts_by_replies, including a continuation from a deleted reply and
--     condenser's continuation, which reads the replied-to author from the start reply;
--   - the walk keeps its shape: hive_replies by hive_replies_parent_author_id_post_id_idx, no
--     sequential scan of it, and for a short page fewer index tuples than the author's replies.
-- Seeds its own accounts, posts and replies in a transaction it rolls back, so it runs on any
-- installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/get_account_posts_replies_generic_plan.sql
--
-- gar-author writes gar-root-1 .. gar-root-4; gar-root-4 is deleted. gar-replier-1 .. gar-replier-3
-- write gar-re-1 .. gar-re-24 in turn: gar-re-1 .. gar-re-21 reply to gar-root-1 .. gar-root-3,
-- gar-re-22 and gar-re-23 to the deleted gar-root-4, and gar-re-24 replies to gar-root-1 and is
-- deleted. gar-author answers gar-re-1 with gar-re-25, a reply to gar-replier-1, not to gar-author.
-- gar-observer mutes gar-replier-2. gar-other-1 .. gar-other-100 each hold 50 hive_replies rows of no
-- post, so that the average author's share of hive_replies is small, as on a synced node.

\set ON_ERROR_STOP 1
BEGIN;

-- get_account_posts_by_replies as it was before get_account_replies_page
CREATE FUNCTION pg_temp.old_get_account_posts_by_replies(IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _permlink_was_not_empty BOOLEAN, IN _called_from_bridge_api BOOLEAN, IN _votes_mode SMALLINT DEFAULT 0, IN _top_votes INT DEFAULT 0)
RETURNS JSONB

LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_result JSONB;
BEGIN
  IF NOT _called_from_bridge_api and _permlink_was_not_empty THEN
    SELECT pp.author_id INTO _account_id
    FROM hivemind_app.hive_posts hp
    JOIN hivemind_app.hive_posts pp ON hp.parent_id = pp.id
    WHERE hp.id = _post_id;
    IF _account_id = -1 THEN _account_id = NULL; END IF;
  END IF;

  _result = (
    SELECT jsonb_agg (
        -- in python code i saw in that case is_pinned should be set, but I couldn't find an example in db to do a test case.
    ( 
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, NULL, True, True, NULL, _votes_mode, _top_votes)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(_observer_id, row, _truncate_body, False)
      END
    )
    ) FROM (      -- get_account_posts_by_replies
      WITH 
      all_unmuted_replies AS
      (
        -- Newest first down hive_replies_parent_author_id_post_id_idx, stopping after _limit live, unmuted replies
        -- to live posts. The bound is one expression of the arguments, so a generic plan keeps it an index condition.
        SELECT hpr.id
        FROM hivemind_app.hive_replies hr
        JOIN hivemind_app.live_posts_comments_view hpr ON hpr.id = hr.post_id
        JOIN hivemind_app.live_posts_comments_view hp ON hp.id = hpr.parent_id
        WHERE
          hr.parent_author_id = _account_id
          AND hr.post_id < COALESCE(NULLIF(_post_id, 0), 2147483647)
          AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hpr.author_id))
        ORDER BY hr.post_id DESC
        LIMIT _limit
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
      FROM all_unmuted_replies,
      LATERAL hivemind_app.get_full_post_view_by_id(all_unmuted_replies.id, _observer_id) hp
      ORDER BY all_unmuted_replies.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

ALTER FUNCTION pg_temp.old_get_account_posts_by_replies SET enable_mergejoin = off;
ALTER FUNCTION pg_temp.old_get_account_posts_by_replies SET enable_hashjoin = off;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['gar-author', 'gar-replier-1', 'gar-replier-2', 'gar-replier-3', 'gar-observer'] || ARRAY(SELECT 'gar-other-' || i FROM generate_series(1, 100) i)) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'gar-root-' || i FROM generate_series(1, 4) i
UNION ALL SELECT 'gar-re-' || i FROM generate_series(1, 25) i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('gar-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, counter_deleted, block_num, block_num_created)
SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')), 0, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gar-author'), pd.id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gar-cat'),
  '2016-07-01'::TIMESTAMP + substr(pd.permlink, 10)::INT * INTERVAL '1 hour', 0,
  CASE WHEN pd.permlink = 'gar-root-4' THEN 1 ELSE 0 END, 1, 1
FROM hivemind_app.hive_permlink_data pd WHERE pd.permlink LIKE 'gar-root-%'
ORDER BY substr(pd.permlink, 10)::INT;
UPDATE hivemind_app.hive_posts hp SET root_id = hp.id
FROM hivemind_app.hive_permlink_data pd WHERE pd.id = hp.permlink_id AND pd.permlink LIKE 'gar-root-%';

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, counter_deleted, block_num, block_num_created)
SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')), parent.id, parent.id,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gar-replier-' || ((r.n - 1) % 3 + 1)), r.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gar-cat'),
  '2016-07-02'::TIMESTAMP + r.n * INTERVAL '1 hour', 1,
  CASE WHEN r.n = 24 THEN 1 ELSE 0 END, 1, 1
FROM (SELECT pd.id AS permlink_id, substr(pd.permlink, 8)::INT AS n FROM hivemind_app.hive_permlink_data pd
      WHERE pd.permlink LIKE 'gar-re-%' AND pd.permlink <> 'gar-re-25') r
JOIN hivemind_app.hive_permlink_data ppd ON ppd.permlink = 'gar-root-' || CASE WHEN r.n IN (22, 23) THEN 4 WHEN r.n = 24 THEN 1 ELSE (r.n - 1) % 3 + 1 END
JOIN hivemind_app.hive_posts parent ON parent.permlink_id = ppd.id
ORDER BY r.n;
INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')), parent.root_id, parent.id,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gar-author'), pd.id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gar-cat'), '2016-07-05', 2, 1, 1
FROM hivemind_app.hive_permlink_data pd, hivemind_app.hive_posts parent
JOIN hivemind_app.hive_permlink_data ppd ON ppd.id = parent.permlink_id
WHERE pd.permlink = 'gar-re-25' AND ppd.permlink = 'gar-re-1';

INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, hpd.permlink, 'body of ' || hpd.permlink, '{}'
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink LIKE 'gar-root-%' OR hpd.permlink LIKE 'gar-re-%';

INSERT INTO hivemind_app.hive_replies (parent_author_id, post_id)
SELECT parent.author_id, hp.id
FROM hivemind_app.hive_posts hp
JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
JOIN hivemind_app.hive_posts parent ON parent.id = hp.parent_id
WHERE hpd.permlink LIKE 'gar-re-%';

INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'gar-observer' AND m.name = 'gar-replier-2';
-- replies to other authors, so that hive_replies is not small enough to read whole
INSERT INTO hivemind_app.hive_replies (parent_author_id, post_id)
SELECT a.id, p FROM hivemind_app.hive_accounts a, generate_series(1, 50) p
WHERE a.name LIKE 'gar-other-%';

ANALYZE hivemind_app.hive_replies, hivemind_app.hive_posts;

DO $$
DECLARE
  _config TEXT[] := (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_account_replies_page(INT, INT, INT, INT)'::regprocedure);
  _author_id INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gar-author');
  _observer_id INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gar-observer');
  _held INT := (SELECT count(*) FROM hivemind_app.hive_replies WHERE parent_author_id = (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gar-author'));
  _start TEXT;
  _start_id INT;
  _start_author_id INT;
  _account_id INT;
  _bridge BOOLEAN;
  _observer INT;
  _limit INT;
  _what TEXT;
  _r JSONB;
  _old JSONB;
  _calls INT := 0;
  _seq BIGINT;
  _idx_scans BIGINT;
  _tuples BIGINT;
BEGIN
  IF _config IS DISTINCT FROM ARRAY['plan_cache_mode=force_generic_plan'] THEN
    RAISE EXCEPTION 'get_account_replies_page is configured %, expected only plan_cache_mode=force_generic_plan', _config;
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_account_posts_by_replies(INT, INT, INT, INT, INT, BOOLEAN, BOOLEAN, SMALLINT, INT)'::regprocedure) IS NOT NULL THEN
    RAISE EXCEPTION 'get_account_posts_by_replies carries planner settings, which would hold for the functions it calls';
  END IF;

  FOR _rep IN 1..3 LOOP
    FOREACH _start IN ARRAY ARRAY[NULL, 'gar-re-20', 'gar-re-12', 'gar-re-24', 'gar-re-1'] LOOP
      SELECT hp.id, hp.author_id INTO _start_id, _start_author_id
      FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id WHERE hpd.permlink = _start;
      _start_id = COALESCE(_start_id, 0);
      FOREACH _bridge IN ARRAY ARRAY[true, false] LOOP
        -- condenser names the start reply's author and pages from it; bridge names the replied-to author
        _account_id = CASE WHEN NOT _bridge AND _start IS NOT NULL THEN _start_author_id ELSE _author_id END;
        FOREACH _observer IN ARRAY ARRAY[-1, _observer_id] LOOP
          FOREACH _limit IN ARRAY ARRAY[3, 20] LOOP
            _what = format('call %s start %s bridge %s observer %s limit %s', _rep, _start, _bridge, _observer, _limit);
            _seq = pg_stat_get_xact_numscans('hivemind_app.hive_replies'::regclass);
            _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_replies_parent_author_id_post_id_idx'::regclass);
            _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_replies_parent_author_id_post_id_idx'::regclass);

            _r = hivemind_postgrest_utilities.get_account_posts_by_replies(_account_id, _start_id, _observer, _limit, 0, _start IS NOT NULL, _bridge);

            _seq = pg_stat_get_xact_numscans('hivemind_app.hive_replies'::regclass) - _seq;
            _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_replies_parent_author_id_post_id_idx'::regclass) - _idx_scans;
            _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_replies_parent_author_id_post_id_idx'::regclass) - _tuples;
            _calls = _calls + 1;

            _old = pg_temp.old_get_account_posts_by_replies(_account_id, _start_id, _observer, _limit, 0, _start IS NOT NULL, _bridge);
            IF _r IS DISTINCT FROM _old THEN
              RAISE EXCEPTION '%: % differs from the pre-change answer %', _what, left(_r::TEXT, 600), left(_old::TEXT, 600);
            END IF;
            IF _start IS DISTINCT FROM 'gar-re-1' AND jsonb_array_length(_r) = 0 THEN
              RAISE EXCEPTION '%: an empty page', _what;
            END IF;
            IF _start = 'gar-re-1' AND jsonb_array_length(_r) <> 0 THEN
              RAISE EXCEPTION '%: a page after the oldest reply: %', _what, left(_r::TEXT, 600);
            END IF;
            IF _r @> '[{"permlink": "gar-re-22"}]' OR _r @> '[{"permlink": "gar-re-23"}]' OR _r @> '[{"permlink": "gar-re-24"}]' OR _r @> '[{"permlink": "gar-re-25"}]' THEN
              RAISE EXCEPTION '%: lists a deleted reply, a reply to a deleted post or a reply to another author: %', _what, left(_r::TEXT, 600);
            END IF;
            IF _observer = _observer_id AND _r @> '[{"author": "gar-replier-2"}]' THEN
              RAISE EXCEPTION '%: lists a reply by the replier the observer mutes', _what;
            END IF;
            IF _start IS NULL AND _limit = 20 AND _observer = -1 AND jsonb_array_length(_r) <> 20 THEN
              RAISE EXCEPTION '%: % replies on a first page of 20, expected 20 of the 21 live ones', _what, jsonb_array_length(_r);
            END IF;

            IF _seq <> 0 THEN
              RAISE EXCEPTION '%: % sequential scans of hive_replies, expected none', _what, _seq;
            END IF;
            IF _idx_scans = 0 THEN
              RAISE EXCEPTION '%: never scanned hive_replies_parent_author_id_post_id_idx', _what;
            END IF;
            IF _limit = 3 AND _tuples >= _held THEN
              RAISE EXCEPTION '%: % tuples from hive_replies_parent_author_id_post_id_idx for a page of 3 of % replies', _what, _tuples, _held;
            END IF;
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'get_account_posts_by_replies: % calls on the generic walk, answers equal to the pre-change body', _calls;
END
$$;

ROLLBACK;
