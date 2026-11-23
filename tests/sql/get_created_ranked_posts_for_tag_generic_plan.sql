-- get_created_ranked_posts_for_tag reads its page of the tag's posts through get_created_tag_page,
-- whose per-case statements run as cached generic plans (SET plan_cache_mode =
-- force_generic_plan). Over more than five calls of each case in one session (first page and
-- continuation; no observer, an observer who mutes an author, and muted-reasons masks; bridge and
-- condenser), this checks that:
--   - get_created_tag_page carries that setting and get_created_ranked_posts_for_tag none;
--   - every call answers exactly what the body before the helper answers, installed below as
--     pg_temp.old_get_created_ranked_posts_for_tag, including continuations from a deleted post,
--     from a grayed author's post, from below every post and from a post of no such id;
--   - the walk keeps its shape: hive_post_tags by hive_post_tags_tag_id_post_id_idx, no sequential
--     scan of hive_posts or hive_post_tags, and for a short first page fewer index tuples than the tag holds.
-- Seeds its own accounts, posts and tag in a transaction it rolls back, so it runs on any
-- installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/get_created_ranked_posts_for_tag_generic_plan.sql
--
-- gct-author writes gct-1 .. gct-40 under gct-tag, in that id order; gct-12 is deleted and
-- gct-9 .. gct-11 muted for reason 1. gct-muted writes gct-41 .. gct-44, and gct-observer mutes
-- gct-muted. gct-grayed, whose reputation grays it, writes the newest, gct-45 and gct-46. Every
-- post also carries the tags gct-other-1 .. gct-other-120. Before them gct-author writes 4000
-- posts gct-filler-1 .. gct-filler-4000 under none of those tags, so that the tag holds a small
-- share of hive_posts, as a real tag does, and walking hive_posts by id is not the cheap way to it.

\set ON_ERROR_STOP 1
BEGIN;

-- get_created_ranked_posts_for_tag as it was before get_created_tag_page
CREATE FUNCTION pg_temp.old_get_created_ranked_posts_for_tag(IN _post_id INT, IN _observer_id INT, IN _limit INT, IN _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN, IN _muted_reasons_filter_mask INT DEFAULT NULL, IN _votes_mode SMALLINT DEFAULT 0, IN _top_votes INT DEFAULT 0)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_tag_id INT;
_result JSONB;
BEGIN
  _tag_id = hivemind_postgrest_utilities.find_tag_id( _tag, True );

  _result = (
    SELECT jsonb_agg (
    ( 
      CASE
        WHEN _called_from_bridge_api THEN hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, NULL, row.is_pinned, True, NULL, _votes_mode, _top_votes)
        ELSE hivemind_postgrest_utilities.create_condenser_post_object(_observer_id, row, _truncate_body, False)
      END
    )
    ) FROM (
      WITH -- get_created_ranked_posts_for_tag
      tag_posts as
      (
        SELECT
          hp.id
        FROM hivemind_app.live_posts_view hp
        JOIN hivemind_app.hive_post_tags hpt ON hpt.post_id = hp.id
        JOIN hivemind_app.hive_accounts_view ha ON hp.author_id = ha.id
        WHERE
          hpt.tag_id = _tag_id
          AND (_post_id = 0 OR hp.id < _post_id)
          AND NOT ha.is_grayed
          AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
          AND (_muted_reasons_filter_mask IS NULL OR _muted_reasons_filter_mask = 0
              OR (hp.muted_reasons & _muted_reasons_filter_mask) = 0)
        ORDER BY hp.id DESC
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
      FROM tag_posts,
      LATERAL hivemind_app.get_full_post_view_by_id(tag_posts.id, _observer_id) hp
      ORDER BY
        hp.id DESC
      LIMIT _limit
    ) row
  );

  RETURN COALESCE(_result, '[]'::jsonb);
END
$$
;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['gct-author', 'gct-muted', 'gct-observer', 'gct-grayed']) WITH ORDINALITY AS a(name, n);
-- hive_accounts_view reads the reputation from whichever schema reputation_tracker is installed in
DO $$
DECLARE
  _reputations REGCLASS := (
    SELECT DISTINCT d.refobjid::REGCLASS
    FROM pg_rewrite r JOIN pg_depend d ON d.classid = 'pg_rewrite'::REGCLASS AND d.objid = r.oid
    WHERE r.ev_class = 'hivemind_app.hive_accounts_view'::REGCLASS AND d.refobjid::REGCLASS::TEXT LIKE '%account_reputations');
BEGIN
  EXECUTE format('INSERT INTO %s (account_id, reputation, is_implicit) SELECT id, -1000000000000, false FROM hivemind_app.hive_accounts WHERE name = %L', _reputations, 'gct-grayed');
END
$$;
INSERT INTO hivemind_app.hive_permlink_data (permlink) SELECT 'gct-filler-' || i FROM generate_series(1, 4000) i;
INSERT INTO hivemind_app.hive_permlink_data (permlink) SELECT 'gct-' || i FROM generate_series(1, 46) i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('gct-tag');
INSERT INTO hivemind_app.hive_tag_data (tag) VALUES ('gct-tag');

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created)
SELECT p.id, p.id, 0, (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gct-author'), p.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gct-tag'), '2016-07-01', 0, 1, 1
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, permlink_id
      FROM (SELECT pd.id AS permlink_id FROM hivemind_app.hive_permlink_data pd WHERE pd.permlink LIKE 'gct-filler-%' ORDER BY pd.id) ordered) p;
INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, created_at, depth, block_num, block_num_created, counter_deleted, muted_reasons)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = CASE WHEN p.n > 44 THEN 'gct-grayed' WHEN p.n > 40 THEN 'gct-muted' ELSE 'gct-author' END),
  p.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'gct-tag'),
  '2016-07-01'::TIMESTAMP + p.n * INTERVAL '1 hour', 0, 1, 1,
  CASE WHEN p.n = 12 THEN 1 ELSE 0 END,
  CASE WHEN p.n BETWEEN 9 AND 11 THEN 1 ELSE 0 END
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, permlink_id, n
      FROM (SELECT pd.id AS permlink_id, substr(pd.permlink, 5)::INT AS n
            FROM hivemind_app.hive_permlink_data pd WHERE pd.permlink ~ '^gct-[0-9]+$' ORDER BY n) ordered) p;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, hpd.permlink, 'body of ' || hpd.permlink, '{}'
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink ~ '^gct-[0-9]+$';
INSERT INTO hivemind_app.hive_post_tags (post_id, tag_id)
SELECT hp.id, (SELECT id FROM hivemind_app.hive_tag_data WHERE tag = 'gct-tag')
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink ~ '^gct-[0-9]+$';
-- other tags of the same posts, so that hive_post_tags is not small enough to read whole
INSERT INTO hivemind_app.hive_tag_data (tag) SELECT 'gct-other-' || i FROM generate_series(1, 120) i;
INSERT INTO hivemind_app.hive_post_tags (post_id, tag_id)
SELECT hp.id, htd.id
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id, hivemind_app.hive_tag_data htd
WHERE hpd.permlink ~ '^gct-[0-9]+$' AND htd.tag LIKE 'gct-other-%';

INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'gct-observer' AND m.name = 'gct-muted';

ANALYZE hivemind_app.hive_posts, hivemind_app.hive_post_tags;

DO $$
DECLARE
  _config TEXT[] := (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_created_tag_page(INT, INT, INT, INT, INT)'::regprocedure);
  _observer_id INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'gct-observer');
  _held INT := 46;
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
  IF _config IS DISTINCT FROM ARRAY['plan_cache_mode=force_generic_plan'] THEN
    RAISE EXCEPTION 'get_created_tag_page is configured %, expected plan_cache_mode=force_generic_plan', _config;
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_created_ranked_posts_for_tag(INT, INT, INT, INT, TEXT, BOOLEAN, INT, SMALLINT, INT)'::regprocedure) IS NOT NULL THEN
    RAISE EXCEPTION 'get_created_ranked_posts_for_tag carries planner settings, which would hold for the functions it calls';
  END IF;

  FOR _rep IN 1..2 LOOP
    FOREACH _start IN ARRAY ARRAY[NULL, 'gct-20', 'gct-12', 'gct-46', 'below', 'none'] LOOP
      _start_id = CASE _start
        WHEN 'none' THEN 2147483000
        WHEN 'below' THEN 1
        ELSE COALESCE((SELECT hp.id FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id WHERE hpd.permlink = _start), 0)
      END;
      FOREACH _observer IN ARRAY ARRAY[-1, _observer_id] LOOP
        FOREACH _mask IN ARRAY ARRAY[NULL, 0, 1] LOOP
          FOREACH _bridge IN ARRAY ARRAY[true, false] LOOP
            FOREACH _limit IN ARRAY ARRAY[3, 20] LOOP
              _what = format('call %s start %s observer %s mask %s bridge %s limit %s', _rep, _start, _observer, _mask, _bridge, _limit);
              _seq = pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_post_tags'::regclass);
              _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_post_tags_tag_id_post_id_idx'::regclass);
              _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_post_tags_tag_id_post_id_idx'::regclass);

              _r = hivemind_postgrest_utilities.get_created_ranked_posts_for_tag(_start_id, _observer, _limit, 0, 'gct-tag', _bridge, _mask);

              _seq = pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass) + pg_stat_get_xact_numscans('hivemind_app.hive_post_tags'::regclass) - _seq;
              _idx_scans = pg_stat_get_xact_numscans('hivemind_app.hive_post_tags_tag_id_post_id_idx'::regclass) - _idx_scans;
              _tuples = pg_stat_get_xact_tuples_returned('hivemind_app.hive_post_tags_tag_id_post_id_idx'::regclass) - _tuples;
              _calls = _calls + 1;

              _old = pg_temp.old_get_created_ranked_posts_for_tag(_start_id, _observer, _limit, 0, 'gct-tag', _bridge, _mask);
              IF _r IS DISTINCT FROM _old THEN
                RAISE EXCEPTION '%: % differs from the pre-change answer %', _what, left(_r::TEXT, 600), left(_old::TEXT, 600);
              END IF;
              IF _start IS DISTINCT FROM 'below' AND jsonb_array_length(_r) = 0 THEN
                RAISE EXCEPTION '%: an empty page', _what;
              END IF;
              IF _start = 'below' AND jsonb_array_length(_r) <> 0 THEN
                RAISE EXCEPTION '%: a page below every post: %', _what, left(_r::TEXT, 600);
              END IF;
              IF _r @> '[{"permlink": "gct-12"}]' THEN
                RAISE EXCEPTION '%: lists the deleted gct-12', _what;
              END IF;
              IF _r @> '[{"author": "gct-grayed"}]' THEN
                RAISE EXCEPTION '%: lists a post of the grayed gct-grayed', _what;
              END IF;
              IF _observer <> -1 AND _r @> '[{"author": "gct-muted"}]' THEN
                RAISE EXCEPTION '%: lists a post of the muted gct-muted', _what;
              END IF;
              IF _mask = 1 AND _r @> '[{"permlink": "gct-10"}]' THEN
                RAISE EXCEPTION '%: lists gct-10, muted for a reason the mask filters', _what;
              END IF;

              IF _seq <> 0 THEN
                RAISE EXCEPTION '%: % sequential scans of hive_posts and hive_post_tags, expected none', _what, _seq;
              END IF;
              IF _idx_scans = 0 THEN
                RAISE EXCEPTION '%: never scanned hive_post_tags_tag_id_post_id_idx', _what;
              END IF;
              IF _start IS NULL AND _limit = 3 AND _tuples >= _held THEN
                RAISE EXCEPTION '%: % tuples from hive_post_tags_tag_id_post_id_idx for a first page of 3 of a tag of %', _what, _tuples, _held;
              END IF;
            END LOOP;
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'get_created_ranked_posts_for_tag: % calls on the generic walk, answers equal to the pre-change body', _calls;
END
$$;

ROLLBACK;
