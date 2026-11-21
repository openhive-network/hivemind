-- get_account_posts_by_blog reads its page of hive_feed_cache through get_account_blog_page,
-- whose per-case statements run as cached generic plans (SET plan_cache_mode =
-- force_generic_plan). Over more than five calls of each case in one session (bridge and
-- condenser, first page and continuation, with and without an observer who mutes the blogger),
-- this checks that:
--   - get_account_blog_page carries the setting and get_account_posts_by_blog none of its own;
--   - every call answers exactly what the body before the helper answers, installed below as
--     pg_temp.old_get_account_posts_by_blog, including a continuation from a post that is not
--     on the blog and from posts that share a created_at;
--   - the walk keeps its shape: hive_feed_cache by hive_feed_cache_account_id_created_at_post_id_idx,
--     no sequential scan of it, and for a short page fewer index tuples than the blog holds.
-- Seeds its own accounts, posts and blog in a transaction it rolls back, so it runs on any
-- installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/get_account_posts_blog_generic_plan.sql
--
-- gab-blogger writes gab-own-1 .. gab-own-30 (pairs share a created_at; gab-own-26 .. gab-own-30
-- are in community hive-506001) and reblogs gab-other's gab-reb-1 .. gab-reb-6 (gab-reb-5 and
-- gab-reb-6 in the community). gab-reb-7 is not on the blog. gab-observer mutes gab-blogger.
-- gab-other and gab-observer each hold 5000 blog rows of no post.

\set ON_ERROR_STOP 1
BEGIN;

-- get_account_posts_by_blog as it was before get_account_blog_page
CREATE FUNCTION pg_temp.old_get_account_posts_by_blog(IN _account TEXT, IN _account_id INT, IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _called_from_bridge_api BOOLEAN, IN _votes_mode SMALLINT DEFAULT 0, IN _top_votes INT DEFAULT 0)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_created_at TIMESTAMP;
_posts_should_be_grayed BOOLEAN;
_result JSONB;
BEGIN
  IF _post_id <> 0 THEN
    SELECT hfc.created_at INTO _created_at
    FROM hivemind_app.hive_feed_cache hfc
    WHERE hfc.account_id = _account_id AND hfc.post_id = _post_id;
  END IF;
  -- DLN maybe this should  be changed to a straight mute instead of graying
  IF _observer_id <> -1 AND EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = _account_id) THEN
    _posts_should_be_grayed = True;
  ELSE
    _posts_should_be_grayed = False;
  END IF;

  _result = (
    SELECT jsonb_agg (
    (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, (CASE WHEN row.author <> _account THEN ARRAY[_account] ELSE NULL END), False, True, NULL, _votes_mode, _top_votes)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(_observer_id, row, _truncate_body, False)
      END
    ) 
    ) FROM (
      WITH blog AS MATERIALIZED -- get_account_posts_by_blog
      (
        SELECT 
          hfc.post_id,
          hfc.created_at,
          hfc.account_id
        FROM hivemind_app.hive_feed_cache hfc
        WHERE hfc.account_id = _account_id         -- use hive_feed_cache_account_id_created_at_post_id_idx
          AND ( _post_id = 0 OR hfc.created_at < _created_at 
                             OR (hfc.created_at = _created_at AND hfc.post_id < _post_id) )
          AND ( NOT _called_from_bridge_api OR
            NOT EXISTS (SELECT NULL FROM hivemind_app.live_posts_view hp1
                        WHERE hp1.id = hfc.post_id AND hp1.community_id IS NOT NULL
                        AND NOT EXISTS (SELECT NULL FROM hivemind_app.hive_reblogs hr WHERE hr.blogger_id = _account_id AND hr.post_id = hp1.id)
                       )
          )
        ORDER BY hfc.created_at DESC, hfc.post_id DESC
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
        -- is grayed - if author is muted by observer, make post gray
        hp.is_grayed OR _posts_should_be_grayed AS is_grayed,
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
      FROM blog,
      LATERAL hivemind_app.get_full_post_view_by_id(blog.post_id, _observer_id) hp
      ORDER BY blog.created_at DESC, blog.post_id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['gab-blogger', 'gab-other', 'gab-observer']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_communities (id, type_id, name, created_at, block_num)
SELECT (SELECT COALESCE(max(id), 0) FROM hivemind_app.hive_communities) + 1, 1, 'hive-506001', '2016-06-01', 1;
INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'gab-own-' || i FROM generate_series(1, 30) i
UNION ALL SELECT 'gab-reb-' || i FROM generate_series(1, 7) i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('gab-cat');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, community_id, created_at, depth, block_num, block_num_created)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = CASE WHEN p.own THEN 'gab-blogger' ELSE 'gab-other' END),
  p.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gab-cat'),
  CASE WHEN (p.own AND p.n > 25) OR (NOT p.own AND p.n IN (5, 6)) THEN (SELECT id FROM hivemind_app.hive_communities WHERE name = 'hive-506001') END,
  '2016-07-01'::TIMESTAMP + (CASE WHEN p.own THEN (p.n + 1) / 2 ELSE p.n * 3 END) * INTERVAL '1 hour', 0, 1, 1
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, pd.id AS permlink_id,
             pd.permlink LIKE 'gab-own-%' AS own, substr(pd.permlink, 9)::INT AS n
      FROM hivemind_app.hive_permlink_data pd WHERE pd.permlink LIKE 'gab-own-%' OR pd.permlink LIKE 'gab-reb-%'
      ORDER BY pd.permlink LIKE 'gab-own-%' DESC, substr(pd.permlink, 9)::INT) p;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, hpd.permlink, 'body of ' || hpd.permlink, '{}'
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink LIKE 'gab-own-%' OR hpd.permlink LIKE 'gab-reb-%';

INSERT INTO hivemind_app.hive_reblogs (blogger_id, post_id, created_at, block_num)
SELECT (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gab-blogger'), hp.id, hp.created_at + INTERVAL '10 minutes', 1
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink LIKE 'gab-reb-%' AND hpd.permlink <> 'gab-reb-7';
INSERT INTO hivemind_app.hive_feed_cache (post_id, account_id, created_at, block_num)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gab-blogger'), COALESCE(hr.created_at, hp.created_at), 1
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
LEFT JOIN hivemind_app.hive_reblogs hr ON hr.post_id = hp.id
WHERE hpd.permlink LIKE 'gab-own-%' OR (hpd.permlink LIKE 'gab-reb-%' AND hpd.permlink <> 'gab-reb-7');

INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'gab-observer' AND m.name = 'gab-blogger';
-- other blogs, so that hive_feed_cache is not small enough to read whole
INSERT INTO hivemind_app.hive_feed_cache (post_id, account_id, created_at, block_num)
SELECT p, a.id, '2016-07-01'::TIMESTAMP + p * INTERVAL '1 minute', 1
FROM hivemind_app.hive_accounts a, generate_series(1, 5000) p
WHERE a.name IN ('gab-other', 'gab-observer');

ANALYZE hivemind_app.hive_feed_cache, hivemind_app.hive_posts, hivemind_app.hive_reblogs;

DO $$
DECLARE
  _config TEXT[] := (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_account_blog_page(INT, INT, INT, BOOLEAN)'::regprocedure);
  _blogger_id INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gab-blogger');
  _observer_id INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gab-observer');
  _held INT := (SELECT count(*) FROM hivemind_app.hive_feed_cache WHERE account_id = (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gab-blogger'));
  _start TEXT;
  _start_id INT;
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
    RAISE EXCEPTION 'get_account_blog_page is configured %, expected only plan_cache_mode=force_generic_plan', _config;
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_account_posts_by_blog(TEXT, INT, INT, INT, INT, INT, BOOLEAN, SMALLINT, INT)'::regprocedure) IS NOT NULL THEN
    RAISE EXCEPTION 'get_account_posts_by_blog carries planner settings, which would hold for the functions it calls';
  END IF;

  FOR _rep IN 1..3 LOOP
    FOREACH _start IN ARRAY ARRAY[NULL, 'gab-own-20', 'gab-own-19', 'gab-reb-3', 'gab-reb-7'] LOOP
      _start_id = COALESCE((SELECT hp.id FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id WHERE hpd.permlink = _start), 0);
      FOREACH _bridge IN ARRAY ARRAY[true, false] LOOP
        FOREACH _observer IN ARRAY ARRAY[-1, _observer_id] LOOP
          FOREACH _limit IN ARRAY ARRAY[3, 20] LOOP
            _what = format('call %s start %s bridge %s observer %s limit %s', _rep, _start, _bridge, _observer, _limit);
            _seq = pg_stat_get_xact_numscans('hivemind_app.hive_feed_cache'::regclass);
            _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_feed_cache_account_id_created_at_post_id_idx'::regclass);
            _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_feed_cache_account_id_created_at_post_id_idx'::regclass);

            _r = hivemind_postgrest_utilities.get_account_posts_by_blog('gab-blogger', _blogger_id, _start_id, _observer, _limit, 0, _bridge);

            _seq = pg_stat_get_xact_numscans('hivemind_app.hive_feed_cache'::regclass) - _seq;
            _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_feed_cache_account_id_created_at_post_id_idx'::regclass) - _idx_scans;
            _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_feed_cache_account_id_created_at_post_id_idx'::regclass) - _tuples;
            _calls = _calls + 1;

            _old = pg_temp.old_get_account_posts_by_blog('gab-blogger', _blogger_id, _start_id, _observer, _limit, 0, _bridge);
            IF _r IS DISTINCT FROM _old THEN
              RAISE EXCEPTION '%: % differs from the pre-change answer %', _what, left(_r::TEXT, 600), left(_old::TEXT, 600);
            END IF;
            IF _start IS DISTINCT FROM 'gab-reb-7' AND jsonb_array_length(_r) = 0 THEN
              RAISE EXCEPTION '%: an empty page', _what;
            END IF;
            IF _start = 'gab-reb-7' AND jsonb_array_length(_r) <> 0 THEN
              RAISE EXCEPTION '%: a page after a post not on the blog: %', _what, left(_r::TEXT, 600);
            END IF;
            IF _bridge AND _r @> '[{"permlink": "gab-own-30"}]' THEN
              RAISE EXCEPTION '%: the bridge lists a community post the blogger did not reblog', _what;
            END IF;
            IF _start IS NULL AND _bridge AND NOT _r @> '[{"permlink": "gab-reb-6", "reblogged_by": ["gab-blogger"]}]' THEN
              RAISE EXCEPTION '%: the reblogged community post gab-reb-6 is missing: %', _what, left(_r::TEXT, 600);
            END IF;

            IF _seq <> 0 THEN
              RAISE EXCEPTION '%: % sequential scans of hive_feed_cache, expected none', _what, _seq;
            END IF;
            IF _start IS DISTINCT FROM 'gab-reb-7' AND _idx_scans = 0 THEN
              RAISE EXCEPTION '%: never scanned hive_feed_cache_account_id_created_at_post_id_idx', _what;
            END IF;
            IF _limit = 3 AND _tuples >= _held THEN
              RAISE EXCEPTION '%: % tuples from hive_feed_cache_account_id_created_at_post_id_idx for a page of 3 of a blog of %', _what, _tuples, _held;
            END IF;
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'get_account_posts_by_blog: % calls on the generic walk, answers equal to the pre-change body', _calls;
END
$$;

ROLLBACK;
