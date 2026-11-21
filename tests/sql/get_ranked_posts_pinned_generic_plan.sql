-- get_ranked_posts_for_communities reads a community's pinned posts through
-- get_community_pinned_page, whose per-case statements run as cached generic plans (SET
-- plan_cache_mode = force_generic_plan). Over more than five calls of each case in one session
-- (first page and continuation from a pinned post; no observer, an observer who mutes an author,
-- and muted-reasons masks; trending and created), this checks that:
--   - get_community_pinned_page carries the setting and get_ranked_posts_for_communities none;
--   - every call answers exactly what the body before the helper answers, installed below as
--     pg_temp.old_get_ranked_posts_for_communities;
--   - the pinned walk reads hive_posts by an index (hive_posts_community_id_is_pinned_idx on
--     production's statistics) and never sequentially.
-- Seeds its own accounts, community and posts in a transaction it rolls back, so it runs on any
-- installed hivemind schema:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/get_ranked_posts_pinned_generic_plan.sql
--
-- In community hive-506002, grp-author writes grp-1 .. grp-12, of which grp-1 .. grp-6 are pinned
-- and grp-2 is muted for reason 1; grp-muted writes the pinned grp-13. grp-observer mutes grp-muted.

\set ON_ERROR_STOP 1
BEGIN;

CREATE FUNCTION pg_temp.index_scans(_rel REGCLASS)
RETURNS BIGINT
LANGUAGE sql
AS $$
  SELECT COALESCE(sum(pg_stat_get_xact_numscans(i.indexrelid)), 0)::BIGINT FROM pg_index i WHERE i.indrelid = _rel
$$;

-- get_ranked_posts_for_communities as it was before get_community_pinned_page
CREATE FUNCTION pg_temp.old_get_ranked_posts_for_communities(IN _post_id INT, IN _observer_id INT, IN _limit INT, _truncate_body INT, IN _tag TEXT, IN _called_from_bridge_api BOOLEAN, IN _sort_type hivemind_postgrest_utilities.ranked_post_sort_type, IN _muted_reasons_filter_mask INT DEFAULT NULL, IN _votes_mode SMALLINT DEFAULT 0, IN _top_votes INT DEFAULT 0)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_extract_pinned_posts BOOLEAN DEFAULT False; 
_result JSONB;
BEGIN
  IF _called_from_bridge_api AND _sort_type = ANY(ARRAY['trending'::hivemind_postgrest_utilities.ranked_post_sort_type, 'created'::hivemind_postgrest_utilities.ranked_post_sort_type])
    AND NOT (_post_id <> 0 AND NOT (SELECT is_pinned FROM hivemind_app.hive_posts WHERE id = _post_id LIMIT 1)) THEN
    _extract_pinned_posts = True;
  END IF;

  IF _extract_pinned_posts THEN
    _result = (
      SELECT jsonb_agg (
        hivemind_postgrest_utilities.create_bridge_post_object(_observer_id, row, _truncate_body, NULL, row.is_pinned, True, NULL, _votes_mode, _top_votes)
      ) FROM (
        WITH
        pinned_post AS -- get_ranked_posts_for_communities pinned
        (
          SELECT 
            hp.id
          FROM hivemind_app.live_posts_view hp
          WHERE
            hp.is_pinned
            AND hp.community_id = (SELECT id FROM hivemind_app.hive_communities WHERE name = _tag LIMIT 1) --use hive_posts_community_id_is_pinned_idx
            AND (_post_id = 0 OR hp.id < _post_id)
            AND (_observer_id = -1 OR NOT EXISTS (SELECT 1 FROM hivemind_app.muted_accounts_by_id_view WHERE observer_id = _observer_id AND muted_id = hp.author_id))
            AND (_muted_reasons_filter_mask IS NULL OR _muted_reasons_filter_mask = 0
              OR ((hp.muted_reasons & _muted_reasons_filter_mask) = 0
                  AND NOT ((_muted_reasons_filter_mask & 8) != 0 AND (SELECT is_grayed FROM hivemind_app.hive_accounts_view WHERE id = hp.author_id))
                  AND NOT ((_muted_reasons_filter_mask & 16) != 0 AND EXISTS (SELECT 1 FROM hivemind_app.hive_roles WHERE account_id = hp.author_id AND community_id = hp.community_id AND role_id = -2))))
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
        FROM pinned_post,
        LATERAL hivemind_app.get_full_post_view_by_id(pinned_post.id, _observer_id) hp
        ORDER BY hp.id DESC
        LIMIT _limit
      ) row
    );
  END IF;

  IF _result IS NULL THEN
    _result = '[]'::jsonb;
  ELSE
    _limit = _limit - jsonb_array_length(_result);
  END IF;

  IF _limit > 0 THEN
    CASE _sort_type
      WHEN 'trending' THEN _result = _result || hivemind_postgrest_utilities.get_trending_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api, _muted_reasons_filter_mask, _votes_mode, _top_votes);
      WHEN 'hot' THEN _result = _result || hivemind_postgrest_utilities.get_hot_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api, _muted_reasons_filter_mask, _votes_mode, _top_votes);
      WHEN 'created' THEN _result = _result || hivemind_postgrest_utilities.get_created_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api, _muted_reasons_filter_mask, _votes_mode, _top_votes);
      WHEN 'payout' THEN _result = _result || hivemind_postgrest_utilities.get_payout_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api, _muted_reasons_filter_mask, _votes_mode, _top_votes);
      WHEN 'payout_comments' THEN _result = _result || hivemind_postgrest_utilities.get_payout_comments_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _called_from_bridge_api, _muted_reasons_filter_mask, _votes_mode, _top_votes);
      WHEN 'muted' THEN _result = _result || hivemind_postgrest_utilities.get_muted_ranked_posts_for_communities(_post_id, _observer_id, _limit, _truncate_body, _tag, _muted_reasons_filter_mask, _votes_mode, _top_votes);
    END CASE;
  END IF;

  RETURN _result;
END
$$
;

INSERT INTO hivemind_app.hive_accounts (id, name, created_at)
SELECT (SELECT max(id) FROM hivemind_app.hive_accounts) + a.n, a.name, '2016-06-01'
FROM unnest(ARRAY['grp-author', 'grp-muted', 'grp-observer']) WITH ORDINALITY AS a(name, n);
INSERT INTO hivemind_app.hive_communities (id, type_id, name, created_at, block_num)
SELECT (SELECT COALESCE(max(id), 0) FROM hivemind_app.hive_communities) + 1, 1, 'hive-506002', '2016-06-01', 1;
INSERT INTO hivemind_app.hive_permlink_data (permlink) SELECT 'grp-' || i FROM generate_series(1, 13) i;
INSERT INTO hivemind_app.hive_category_data (category) VALUES ('hive-506002') ON CONFLICT DO NOTHING;

INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, community_id, created_at, depth, block_num, block_num_created, sc_trend, is_pinned, muted_reasons)
SELECT p.id, p.id, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = CASE WHEN p.n = 13 THEN 'grp-muted' ELSE 'grp-author' END),
  p.permlink_id,
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'hive-506002'),
  (SELECT id FROM hivemind_app.hive_communities WHERE name = 'hive-506002'),
  '2016-07-01'::TIMESTAMP + p.n * INTERVAL '1 hour', 0, 1, 1, 100 - p.n,
  p.n <= 6 OR p.n = 13,
  CASE WHEN p.n = 2 THEN 1 ELSE 0 END
FROM (SELECT nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id')) AS id, pd.id AS permlink_id, substr(pd.permlink, 5)::INT AS n
      FROM hivemind_app.hive_permlink_data pd WHERE pd.permlink ~ '^grp-[0-9]+$' ORDER BY n) p;
INSERT INTO hivemind_app.hive_post_data (id, title, body, json)
SELECT hp.id, hpd.permlink, 'body of ' || hpd.permlink, '{}'
FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
WHERE hpd.permlink ~ '^grp-[0-9]+$';

INSERT INTO hivemind_app.muted (follower, following, block_num)
SELECT o.id, m.id, 1 FROM hivemind_app.hive_accounts o, hivemind_app.hive_accounts m
WHERE o.name = 'grp-observer' AND m.name = 'grp-muted';

ANALYZE hivemind_app.hive_posts;

DO $$
DECLARE
  _config TEXT[] := (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_community_pinned_page(TEXT, INT, INT, INT, INT)'::regprocedure);
  _observer_id INT := (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'grp-observer');
  _start TEXT;
  _start_id INT;
  _observer INT;
  _mask INT;
  _sort hivemind_postgrest_utilities.ranked_post_sort_type;
  _limit INT;
  _what TEXT;
  _r JSONB;
  _old JSONB;
  _pinned INT;
  _calls INT := 0;
  _seq BIGINT;
  _idx_scans BIGINT;
BEGIN
  IF _config IS DISTINCT FROM ARRAY['plan_cache_mode=force_generic_plan'] THEN
    RAISE EXCEPTION 'get_community_pinned_page is configured %, expected only plan_cache_mode=force_generic_plan', _config;
  END IF;
  IF (SELECT proconfig FROM pg_proc WHERE oid = 'hivemind_postgrest_utilities.get_ranked_posts_for_communities(INT, INT, INT, INT, TEXT, BOOLEAN, hivemind_postgrest_utilities.ranked_post_sort_type, INT, SMALLINT, INT)'::regprocedure) IS NOT NULL THEN
    RAISE EXCEPTION 'get_ranked_posts_for_communities carries planner settings, which would hold for the functions it calls';
  END IF;

  FOR _rep IN 1..3 LOOP
    FOREACH _start IN ARRAY ARRAY[NULL, 'grp-4', 'grp-13', 'grp-1'] LOOP
      _start_id = COALESCE((SELECT hp.id FROM hivemind_app.hive_posts hp JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id WHERE hpd.permlink = _start), 0);
      FOREACH _observer IN ARRAY ARRAY[-1, _observer_id] LOOP
        FOREACH _mask IN ARRAY ARRAY[NULL, 0, 1] LOOP
          FOREACH _limit IN ARRAY ARRAY[2, 20] LOOP
            _what = format('call %s start %s observer %s mask %s limit %s', _rep, _start, _observer, _mask, _limit);
            _seq = pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass);
            _idx_scans = pg_temp.index_scans('hivemind_app.hive_posts'::regclass);

            _pinned = (SELECT count(*) FROM hivemind_postgrest_utilities.get_community_pinned_page('hive-506002', _start_id, _observer, _limit, _mask));

            _seq = pg_stat_get_xact_numscans('hivemind_app.hive_posts'::regclass) - _seq;
            _idx_scans = pg_temp.index_scans('hivemind_app.hive_posts'::regclass) - _idx_scans;
            IF _seq <> 0 THEN
              RAISE EXCEPTION '%: % sequential scans of hive_posts in the pinned walk, expected none', _what, _seq;
            END IF;
            IF _idx_scans = 0 THEN
              RAISE EXCEPTION '%: the pinned walk read no index of hive_posts', _what;
            END IF;
            IF _pinned > _limit OR (_start IS NULL AND _pinned = 0) THEN
              RAISE EXCEPTION '%: % pinned posts', _what, _pinned;
            END IF;

            FOREACH _sort IN ARRAY ARRAY['trending', 'created']::hivemind_postgrest_utilities.ranked_post_sort_type[] LOOP
              _r = hivemind_postgrest_utilities.get_ranked_posts_for_communities(_start_id, _observer, _limit, 0, 'hive-506002', true, _sort, _mask);
              _calls = _calls + 1;
              _old = pg_temp.old_get_ranked_posts_for_communities(_start_id, _observer, _limit, 0, 'hive-506002', true, _sort, _mask);
              IF _r IS DISTINCT FROM _old THEN
                RAISE EXCEPTION '% %: % differs from the pre-change answer %', _what, _sort, left(_r::TEXT, 600), left(_old::TEXT, 600);
              END IF;
              IF _start IS NULL AND NOT _r->0 @> '{"stats": {"is_pinned": true}}' THEN
                RAISE EXCEPTION '% %: the first page does not open with a pinned post: %', _what, _sort, left(_r::TEXT, 600);
              END IF;
              IF _observer <> -1 AND _r @> '[{"author": "grp-muted"}]' THEN
                RAISE EXCEPTION '% %: lists a post of the muted grp-muted', _what, _sort;
              END IF;
              IF _mask = 1 AND _r @> '[{"permlink": "grp-2"}]' THEN
                RAISE EXCEPTION '% %: lists grp-2, muted for a reason the mask filters', _what, _sort;
              END IF;
            END LOOP;
          END LOOP;
        END LOOP;
      END LOOP;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'get_ranked_posts_for_communities: % calls on the generic pinned walk, answers equal to the pre-change body', _calls;
END
$$;

ROLLBACK;
