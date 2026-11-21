-- get_trending_ranked_posts_for_tag reads its page of the tag's posts through get_trending_tag_page,
-- whose per-case statements run as cached generic plans (SET plan_cache_mode =
-- force_generic_plan, with the enable_sort = false the list held before). Over more than five
-- calls of each case in one session (first page and continuation; no observer, an observer who
-- mutes an author, and muted-reasons masks; bridge and condenser), this checks that:
--   - get_trending_tag_page carries those two settings and get_trending_ranked_posts_for_tag none;
--   - every call answers exactly what the body before the helper answers, installed below as
--     pg_temp.old_get_trending_ranked_posts_for_tag, including continuations from posts that share
--     a sc_trend, from a paid-out post and from a post of no such id;
--   - the walk keeps its shape: hive_posts by hive_posts_sc_trend_id_idx, no sequential scan of
--     hive_posts or hive_post_tags, and for a short first page fewer index tuples than the tag holds.
-- Seeds its own accounts, posts and tag in a transaction it rolls back, so it runs on any
-- installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/get_trending_ranked_posts_for_tag_generic_plan.sql
--
-- gtt-author writes gtt-1 .. gtt-40 under gtt-tag, the sc_trend of gtt-n is 1e9 + 1000 * ((41 - n) / 2), so
-- pairs share it; gtt-5 .. gtt-8 are paid out and gtt-9 .. gtt-11 muted for reason 1. gtt-muted
-- writes gtt-41 .. gtt-44, and gtt-observer mutes gtt-muted. Every post also carries the tags
-- gtt-other-1 .. gtt-other-120.

\set ON_ERROR_STOP 1
BEGIN;

-- get_trending_ranked_posts_for_tag as it was before get_trending_tag_page
CREATE FUNCTION pg_temp.old_get_trending_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN, IN _muted_reasons_filter_mask INT DEFAULT NULL, IN _votes_mode SMALLINT DEFAULT 0, IN _top_votes INT DEFAULT 0)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
set enable_sort=false --Try to enforce using hive_posts_sc_trend_id_idx instead sort in mem which can take a lot of time under load
AS
$$
DECLARE
__trending_limit FLOAT;
_tag_id INT;
_result JSONB;
BEGIN
  _tag_id = hivemind_postgrest_utilities.find_tag_id( _tag, True );

  IF _post_id <> 0 THEN
    SELECT sc_trend INTO __trending_limit FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
  END IF;

  _result = (
    WITH tag_posts AS MATERIALIZED -- get_trending_ranked_posts_for_tag
    (
    SELECT
      hp.id
    FROM hivemind_app.live_posts_view hp
    JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id
    WHERE
      hpt.tag_id = _tag_id AND NOT hp.is_paidout
      AND (_post_id = 0 OR hp.sc_trend < __trending_limit OR (hp.sc_trend = __trending_limit AND hp.id < _post_id))
      AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
          AND (_muted_reasons_filter_mask IS NULL OR _muted_reasons_filter_mask = 0
              OR ((hp.muted_reasons & _muted_reasons_filter_mask) = 0
                  AND NOT ((_muted_reasons_filter_mask & 8) != 0 AND (SELECT is_grayed FROM hivemind_app.hive_accounts_view WHERE id = hp.author_id))
                  AND NOT ((_muted_reasons_filter_mask & 16) != 0 AND EXISTS (SELECT 1 FROM hivemind_app.hive_roles WHERE account_id = hp.author_id AND community_id = hp.community_id AND role_id = -2))))
    ORDER BY
      hp.sc_trend DESC, hp.id DESC
    LIMIT _limit
    )
    ,supplemented_data AS MATERIALIZED
    (
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
    FROM tag_posts,
    LATERAL hivemind_app.get_full_post_view_by_id(tag_posts.id, _observer_id) hp
    )
    SELECT jsonb_agg (
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, sd, _truncate_body, NULL, sd.is_pinned, True, NULL, _votes_mode, _top_votes)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(_observer_id, sd, _truncate_body, False)
      END
      ORDER BY sd.sc_trend DESC, sd.id DESC
    )
    FROM supplemented_data sd
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['gtt-author', 'gtt-muted', 'gtt-observer']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_permlink_data (permlink) SELECT 'gtt-' || i FROM generate_series(1, 44) i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('gtt-tag');
INSERT INTO hivemind_app.hive_tag_data (tag) VALUES ('gtt-tag');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, sc_trend, is_paidout, muted_reasons)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = CASE WHEN p.n > 40 THEN 'gtt-muted' ELSE 'gtt-author' END),
  p.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gtt-tag'),
  '2016-07-01'::TIMESTAMP + p.n * INTERVAL '1 hour', 0, 1, 1,
  1e9 + ((CASE WHEN p.n > 40 THEN 81 - p.n ELSE 41 - p.n END) / 2) * 1000,
  p.n BETWEEN 5 AND 8,
  CASE WHEN p.n BETWEEN 9 AND 11 THEN 1 ELSE 0 END
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, pd.id AS permlink_id, substr(pd.permlink, 5)::INT AS n
      FROM hivemind_app.hive_permlink_data pd WHERE pd.permlink ~ '^gtt-[0-9]+$' ORDER BY n) p;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, hpd.permlink, 'body of ' || hpd.permlink, '{}'
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink ~ '^gtt-[0-9]+$';
INSERT INTO hivemind_app.hive_post_tags (post_id, tag_id)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_tag_data WHERE tag = 'gtt-tag')
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink ~ '^gtt-[0-9]+$';
-- other tags of the same posts, so that hive_post_tags is not small enough to read whole
INSERT INTO hivemind_app.hive_tag_data (tag) SELECT 'gtt-other-' || i FROM generate_series(1, 120) i;
INSERT INTO hivemind_app.hive_post_tags (post_id, tag_id)
SELECT hp.id, htd.id
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id, hivemind_app.hive_tag_data htd
WHERE hpd.permlink ~ '^gtt-[0-9]+$' AND htd.tag LIKE 'gtt-other-%';

INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'gtt-observer' AND m.name = 'gtt-muted';

ANALYZE hivemind_app.hive_posts, hivemind_app.hive_post_tags;

DO $$
DECLARE
  _config TEXT[] := (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_trending_tag_page(INT, INT, INT, INT, INT)'::regprocedure);
  _observer_id INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gtt-observer');
  _held INT := 40;
  _start TEXT;
  _start_id INT;
  _observer INT;
  _mask INT;
  _bridge BOOLEAN;
  _limit INT;
  _what TEXT;
  _r JSONB;
  _old JSONB;
  _calls INT := 0;
  _seq BIGINT;
  _idx_scans BIGINT;
  _tuples BIGINT;
BEGIN
  IF _config IS DISTINCT FROM ARRAY['plan_cache_mode=force_generic_plan', 'enable_sort=false'] THEN
    RAISE EXCEPTION 'get_trending_tag_page is configured %, expected plan_cache_mode=force_generic_plan and enable_sort=false', _config;
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_trending_ranked_posts_for_tag(INT, INT, INT, INT, TEXT, BOOLEAN, INT, SMALLINT, INT)'::regprocedure) IS NOT NULL THEN
    RAISE EXCEPTION 'get_trending_ranked_posts_for_tag carries planner settings, which would hold for the functions it calls';
  END IF;

  FOR _rep IN 1..2 LOOP
    FOREACH _start IN ARRAY ARRAY[NULL, 'gtt-20', 'gtt-21', 'gtt-6', 'none'] LOOP
      _start_id = CASE WHEN _start = 'none' THEN 2147483000 ELSE COALESCE((SELECT hp.id FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id WHERE hpd.permlink = _start), 0) END;
      FOREACH _observer IN ARRAY ARRAY[-1, _observer_id] LOOP
        FOREACH _mask IN ARRAY ARRAY[NULL, 0, 1] LOOP
          FOREACH _bridge IN ARRAY ARRAY[true, false] LOOP
            FOREACH _limit IN ARRAY ARRAY[3, 20] LOOP
              _what = format('call %s start %s observer %s mask %s bridge %s limit %s', _rep, _start, _observer, _mask, _bridge, _limit);
              _seq = pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_post_tags'::regclass);
              _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_posts_sc_trend_id_idx'::regclass);
              _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_posts_sc_trend_id_idx'::regclass);

              _r = hivemind_postgrest_utilities.get_trending_ranked_posts_for_tag(_start_id, _observer, _limit, 0, 'gtt-tag', _bridge, _mask);

              _seq = pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_post_tags'::regclass) - _seq;
              _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_posts_sc_trend_id_idx'::regclass) - _idx_scans;
              _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_posts_sc_trend_id_idx'::regclass) - _tuples;
              _calls = _calls + 1;

              _old = pg_temp.old_get_trending_ranked_posts_for_tag(_start_id, _observer, _limit, 0, 'gtt-tag', _bridge, _mask);
              IF _r IS DISTINCT FROM _old THEN
                RAISE EXCEPTION '%: % differs from the pre-change answer %', _what, left(_r::TEXT, 600), left(_old::TEXT, 600);
              END IF;
              IF (_start IS NULL OR _start LIKE 'gtt-%') AND jsonb_array_length(_r) = 0 THEN
                RAISE EXCEPTION '%: an empty page', _what;
              END IF;
              IF _start = 'none' AND jsonb_array_length(_r) <> 0 THEN
                RAISE EXCEPTION '%: a page after a post of no such id: %', _what, left(_r::TEXT, 600);
              END IF;
              IF _r @> '[{"permlink": "gtt-6"}]' THEN
                RAISE EXCEPTION '%: lists the paid-out gtt-6', _what;
              END IF;
              IF _observer <> -1 AND _r @> '[{"author": "gtt-muted"}]' THEN
                RAISE EXCEPTION '%: lists a post of the muted gtt-muted', _what;
              END IF;
              IF _mask = 1 AND _r @> '[{"permlink": "gtt-10"}]' THEN
                RAISE EXCEPTION '%: lists gtt-10, muted for a reason the mask filters', _what;
              END IF;

              IF _seq <> 0 THEN
                RAISE EXCEPTION '%: % sequential scans of hive_posts and hive_post_tags, expected none', _what, _seq;
              END IF;
              IF _start IS DISTINCT FROM 'none' AND _idx_scans = 0 THEN
                RAISE EXCEPTION '%: never scanned hive_posts_sc_trend_id_idx', _what;
              END IF;
              IF _start IS NULL AND _limit = 3 AND _tuples >= _held THEN
                RAISE EXCEPTION '%: % tuples from hive_posts_sc_trend_id_idx for a first page of 3 of a tag of %', _what, _tuples, _held;
              END IF;
            END LOOP;
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'get_trending_ranked_posts_for_tag: % calls on the generic walk, answers equal to the pre-change body', _calls;
END
$$;

ROLLBACK;
