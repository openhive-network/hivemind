-- process_root_posts_batch, process_comments_batch and process_tags_batch against
-- copies of their implementation before the resolved rows moved to _post_batch and
-- deleted_tags stopped being joined (pg_temp.old_*), on the same seeded posts and ops:
-- the result rows of every wave, the hive_posts rows written (ids included) and the
-- post tags must be identical. The old root batch wrote root_id = 0, which finalization
-- (update_hive_posts_root_id) turned into the post's id; root_id is compared as that
-- leaves it, and the current root batch must write it at insert. Seeds its own accounts, communities, posts
-- and ops in a transaction it rolls back, so it runs on any installed hivemind schema,
-- including an empty chain:
--
--   psql -v ON_ERROR_STOP=1 -d <hivemind url> -f tests/sql/post_batches_staged_join.sql
--
-- One root-post batch of 1,020 ops, then comment waves of 5,040 ops: replies to known
-- and to just-inserted roots, replies two and three levels down (resolved in later
-- waves), known comments again (the ON CONFLICT path), replies to a deleted or unknown
-- post (never resolved), in topic, journal and council communities, before and after
-- the community start block, under muted and unmuted parents. seq_id order differs
-- from permlink order, so ids follow the insert's ORDER BY seq_id.

\set ON_ERROR_STOP 1
BEGIN;

CREATE OR REPLACE FUNCTION pg_temp.old_process_root_posts_batch(
    _ops hivemind_app.hive_post_op_input[]
)
RETURNS SETOF hivemind_app.hive_post_op_result
LANGUAGE plpgsql
AS
$function$
DECLARE
    __member_role CONSTANT SMALLINT := 2;
    __community_type_topic CONSTANT SMALLINT := 1;
    __community_type_journal CONSTANT SMALLINT := 2;
    __community_type_council CONSTANT SMALLINT := 3;
BEGIN
    --- Permlinks and categories are assumed to already be inserted by the caller.

    RETURN QUERY
    WITH ops AS (
        SELECT t.seq_id, t.author, t.permlink, t.parent_permlink,
               t.date, t.community_support_start_block, t.block_num, t.metadata_tags
        FROM unnest(_ops) AS t
    ),
    resolved AS (
        SELECT o.seq_id, o.parent_permlink, o.date, o.block_num, o.metadata_tags,
               o.community_support_start_block,
               ha.id AS author_id,
               hpd.id AS permlink_id,
               hcd.id AS category_id,
               hc.id AS community_id,
               hc.type_id AS community_type_id,
               hr.role_id AS role_id
        FROM ops o
        INNER JOIN hivemind_app.hive_accounts ha ON ha.name = o.author
        INNER JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = o.permlink
        LEFT JOIN hivemind_app.hive_category_data hcd ON hcd.category = o.parent_permlink
        LEFT JOIN hivemind_app.hive_communities hc ON hc.name = o.parent_permlink
                                                   AND o.block_num >= o.community_support_start_block
        LEFT JOIN hivemind_app.hive_roles hr ON hr.community_id = hc.id AND hr.account_id = ha.id
    ),
    with_muting AS (
        SELECT r.*,
            CASE
                WHEN r.community_id IS NULL THEN FALSE
                WHEN r.community_type_id = __community_type_topic THEN FALSE
                WHEN r.community_type_id = __community_type_journal
                     AND r.role_id IS NOT NULL AND r.role_id >= __member_role THEN FALSE
                WHEN r.community_type_id = __community_type_council
                     AND r.role_id IS NOT NULL AND r.role_id >= __member_role THEN FALSE
                WHEN r.community_id IS NOT NULL THEN TRUE
                ELSE FALSE
            END AS is_muted,
            CASE
                WHEN r.community_id IS NOT NULL
                     AND r.community_type_id != __community_type_topic
                     AND NOT (r.community_type_id = __community_type_journal
                              AND r.role_id IS NOT NULL AND r.role_id >= __member_role)
                     AND NOT (r.community_type_id = __community_type_council
                              AND r.role_id IS NOT NULL AND r.role_id >= __member_role)
                THEN hivemind_app.encode_bitwise_mask(ARRAY[1])
                ELSE 0
            END AS muted_reasons
        FROM resolved r
    ),
    inserted AS (
        INSERT INTO hivemind_app.hive_posts AS hp
            (parent_id, depth, community_id, category_id,
             root_id, is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend,
             active, payout_at, cashout_time, counter_deleted, block_num, block_num_created, muted_reasons)
        SELECT
            0, -- parent_id
            0, -- depth
            wm.community_id,
            wm.category_id,
            0, -- root_id (will use id as root)
            wm.is_muted,
            TRUE, -- is_valid
            wm.author_id,
            wm.permlink_id,
            wm.date,
            wm.date,
            hivemind_app.calculate_time_part_of_hot(wm.date),
            hivemind_app.calculate_time_part_of_trending(wm.date),
            wm.date, -- active
            wm.date + INTERVAL '7 days', -- payout_at
            wm.date + INTERVAL '7 days', -- cashout_time
            0, -- counter_deleted
            wm.block_num,
            wm.block_num, -- block_num_created
            wm.muted_reasons
        FROM with_muting wm
        ORDER BY wm.seq_id
        ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
            updated_at = EXCLUDED.updated_at,
            active = EXCLUDED.active,
            block_num = EXCLUDED.block_num
        RETURNING
            (xmax = 0) AS is_new_post,
            hp.id,
            hp.author_id,
            hp.permlink_id,
            hp.parent_id,
            hp.community_id,
            hp.is_valid,
            hp.is_muted,
            hp.depth,
            hp.muted_reasons
    )
    SELECT
        wm.seq_id,
        ins.is_new_post,
        ins.id,
        ins.author_id,
        ins.permlink_id,
        wm.parent_permlink::VARCHAR AS post_category,
        ins.parent_id,
        0, -- parent_author_id (root posts have no parent author)
        ins.community_id,
        ins.is_valid,
        ins.is_muted,
        ins.depth,
        ins.muted_reasons
    FROM inserted ins
    INNER JOIN with_muting wm ON wm.author_id = ins.author_id AND wm.permlink_id = ins.permlink_id;
END
$function$;

CREATE OR REPLACE FUNCTION pg_temp.old_process_comments_batch(
    _ops hivemind_app.hive_post_op_input[]
)
RETURNS SETOF hivemind_app.hive_post_op_result
LANGUAGE plpgsql
AS
$function$
DECLARE
    __member_role CONSTANT SMALLINT := 2;
    __community_type_topic CONSTANT SMALLINT := 1;
    __community_type_journal CONSTANT SMALLINT := 2;
    __community_type_council CONSTANT SMALLINT := 3;
BEGIN
    --- Permlinks are assumed to already be inserted by the caller.

    RETURN QUERY
    WITH ops AS (
        SELECT t.seq_id, t.author, t.permlink, t.parent_author, t.parent_permlink,
               t.date, t.community_support_start_block, t.block_num
        FROM unnest(_ops) AS t
    ),
    resolved AS (
        SELECT o.seq_id, o.date, o.block_num, o.community_support_start_block,
               ha.id AS author_id,
               hpd.id AS permlink_id,
               php.id AS parent_id,
               php.author_id AS parent_author_id,
               php.depth + 1 AS depth,
               COALESCE(php.category_id,
                   (SELECT hcg.id FROM hivemind_app.hive_category_data hcg
                    WHERE hcg.category = o.parent_permlink)) AS category_id,
               CASE php.root_id WHEN 0 THEN php.id ELSE php.root_id END AS root_id,
               php.is_valid AS is_valid,
               php.community_id AS parent_community_id,
               php.is_muted AS parent_is_muted,
               o.parent_permlink
        FROM ops o
        INNER JOIN hivemind_app.hive_accounts ha ON ha.name = o.author
        INNER JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = o.permlink
        INNER JOIN hivemind_app.hive_accounts pha ON pha.name = o.parent_author
        INNER JOIN hivemind_app.hive_permlink_data phpd ON phpd.permlink = o.parent_permlink
        INNER JOIN hivemind_app.hive_posts php
            ON php.author_id = pha.id AND php.permlink_id = phpd.id AND php.counter_deleted = 0
    ),
    with_community AS (
        SELECT r.*,
            CASE
                WHEN r.block_num < r.community_support_start_block THEN NULL
                ELSE r.parent_community_id
            END AS community_id,
            hc.type_id AS community_type_id,
            hr.role_id AS role_id
        FROM resolved r
        LEFT JOIN hivemind_app.hive_communities hc
            ON hc.id = r.parent_community_id AND r.block_num >= r.community_support_start_block
        LEFT JOIN hivemind_app.hive_roles hr
            ON hr.community_id = r.parent_community_id AND hr.account_id = r.author_id
               AND r.block_num >= r.community_support_start_block
    ),
    with_muting AS (
        SELECT wc.*,
            CASE
                --- If parent is muted, child is always muted
                WHEN wc.parent_is_muted THEN TRUE
                --- No community: not muted
                WHEN wc.community_id IS NULL THEN FALSE
                --- Topic communities: never muted
                WHEN wc.community_type_id = __community_type_topic THEN FALSE
                --- Journal communities: comments are never muted by community type
                WHEN wc.community_type_id = __community_type_journal THEN FALSE
                --- Council communities: members are not muted
                WHEN wc.community_type_id = __community_type_council
                     AND wc.role_id IS NOT NULL AND wc.role_id >= __member_role THEN FALSE
                --- Council: non-members are muted
                WHEN wc.community_type_id = __community_type_council THEN TRUE
                ELSE FALSE
            END AS is_muted,
            hivemind_app.encode_bitwise_mask(
                ARRAY_REMOVE(ARRAY[
                    CASE
                        WHEN wc.community_id IS NOT NULL
                             AND wc.community_type_id = __community_type_council
                             AND (wc.role_id IS NULL OR wc.role_id < __member_role)
                        THEN 1 ELSE NULL
                    END,
                    CASE WHEN wc.parent_is_muted THEN 2 ELSE NULL END
                ], NULL)
            ) AS muted_reasons
        FROM with_community wc
    ),
    inserted AS (
        INSERT INTO hivemind_app.hive_posts AS hp
            (parent_id, depth, community_id, category_id,
             root_id, is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, sc_hot, sc_trend,
             active, payout_at, cashout_time, counter_deleted, block_num, block_num_created, muted_reasons)
        SELECT
            wm.parent_id,
            wm.depth::SMALLINT,
            wm.community_id,
            wm.category_id,
            wm.root_id,
            wm.is_muted,
            wm.is_valid,
            wm.author_id,
            wm.permlink_id,
            wm.date,
            wm.date,
            hivemind_app.calculate_time_part_of_hot(wm.date),
            hivemind_app.calculate_time_part_of_trending(wm.date),
            wm.date,
            wm.date + INTERVAL '7 days',
            wm.date + INTERVAL '7 days',
            0,
            wm.block_num,
            wm.block_num,
            wm.muted_reasons
        FROM with_muting wm
        ORDER BY wm.seq_id
        ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
            updated_at = EXCLUDED.updated_at,
            active = EXCLUDED.active,
            block_num = EXCLUDED.block_num
        RETURNING
            (xmax = 0) AS is_new_post,
            hp.id,
            hp.author_id,
            hp.permlink_id,
            hp.parent_id,
            hp.community_id,
            hp.is_valid,
            hp.is_muted,
            hp.depth,
            hp.muted_reasons
    )
    SELECT
        wm.seq_id,
        ins.is_new_post,
        ins.id,
        ins.author_id,
        ins.permlink_id,
        (SELECT hcd.category FROM hivemind_app.hive_category_data hcd WHERE hcd.id = wm.category_id) AS post_category,
        ins.parent_id,
        wm.parent_author_id,
        ins.community_id,
        ins.is_valid,
        ins.is_muted,
        ins.depth,
        ins.muted_reasons
    FROM inserted ins
    INNER JOIN with_muting wm ON wm.author_id = ins.author_id AND wm.permlink_id = ins.permlink_id;
END
$function$;

CREATE OR REPLACE FUNCTION pg_temp.old_process_tags_batch(
    _tags hivemind_app.post_tag_input[]
)
RETURNS VOID
LANGUAGE sql
AS
$function$
--- Data-modifying CTEs must be at the top level (not inside a subquery),
--- so we use LANGUAGE sql where the CTE is the top-level statement.
WITH inputs AS (
    SELECT t.post_id, t.is_new_post,
           CAST(LEFT(LOWER(REGEXP_REPLACE(t.raw_tag, '[#\s]', '', 'g')), 32) AS VARCHAR) AS tag
    FROM unnest(_tags) AS t
),
distinct_tags AS (
    SELECT DISTINCT tag FROM inputs WHERE tag != ''
),
inserted_tags AS (
    INSERT INTO hivemind_app.hive_tag_data AS htd(tag)
    SELECT tag FROM distinct_tags
    ON CONFLICT("tag") DO UPDATE SET tag = EXCLUDED.tag
    RETURNING htd.id, htd.tag
),
tag_map AS (
    SELECT it.id AS tag_id, it.tag FROM inserted_tags it
),
resolved AS (
    SELECT DISTINCT i.post_id, i.is_new_post, tm.tag_id
    FROM inputs i
    INNER JOIN tag_map tm ON tm.tag = i.tag
    WHERE i.tag != ''
),
wanted_tags AS (
    SELECT post_id, array_agg(tag_id) AS tag_ids FROM resolved GROUP BY post_id
),
deleted_tags AS (
    DELETE FROM hivemind_app.hive_post_tags hpt
    USING wanted_tags wt
    WHERE hpt.post_id = wt.post_id
      AND hpt.tag_id != ALL(wt.tag_ids)
      AND EXISTS (SELECT 1 FROM resolved r WHERE r.post_id = wt.post_id AND NOT r.is_new_post)
    RETURNING hpt.post_id
),
inserted_post_tags AS (
    INSERT INTO hivemind_app.hive_post_tags (post_id, tag_id)
    SELECT r.post_id, r.tag_id FROM resolved r
    LEFT JOIN deleted_tags dt ON dt.post_id = 0  -- force evaluation of deleted_tags
    ON CONFLICT DO NOTHING
    RETURNING post_id
)
SELECT post_id FROM inserted_post_tags;
$function$;

INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT 'pb-a' || lpad(i::TEXT, 3, '0'), '2016-06-01' FROM generate_series(1, 200) i ORDER BY i;
INSERT INTO hivemind_app.hive_accounts (name, created_at)
SELECT 'hive-41000' || t, '2016-06-01' FROM generate_series(1, 3) t ORDER BY t;

-- hive-410001 topic, hive-410002 journal, hive-410003 council
INSERT INTO hivemind_app.hive_communities (id, type_id, name, created_at, block_num)
SELECT ha.id, right(ha.name, 1)::SMALLINT, ha.name, '2016-06-01', 100
FROM hivemind_app.hive_accounts ha WHERE ha.name LIKE 'hive-41000_';
-- pb-a001..060 members of the council (pb-a051..060 guests), pb-a001..020 of the journal
INSERT INTO hivemind_app.hive_roles (account_id, community_id, created_at, role_id)
SELECT ha.id, hc.id, '2016-06-01',
  CASE WHEN hc.name = 'hive-410003' AND right(ha.name, 3)::INT > 50 THEN 0 ELSE 2 END
FROM hivemind_app.hive_accounts ha
JOIN hivemind_app.hive_communities hc
  ON (hc.name = 'hive-410003' AND right(ha.name, 3)::INT <= 60)
  OR (hc.name = 'hive-410002' AND right(ha.name, 3)::INT <= 20)
WHERE ha.name LIKE 'pb-a%';

CREATE TEMP TABLE pb_ops (
  seq_id INT, author TEXT, permlink TEXT, parent_author TEXT, parent_permlink TEXT, block_num INT
);
-- Known roots pb-r1..300 (pb-r300 deleted), known comments pb-oc1..20 under them.
-- New roots pb-nr1..1000 and pb-r1..20 again.
INSERT INTO pb_ops (author, permlink, parent_author, parent_permlink, block_num)
SELECT 'pb-a' || lpad((i % 200 + 1)::TEXT, 3, '0'), 'pb-nr' || i, '',
  CASE i % 4 WHEN 0 THEN 'pb-cat' || i % 5 ELSE 'hive-41000' || i % 4 END, 130 + i % 40
FROM generate_series(1, 1000) i
UNION ALL
SELECT 'pb-a' || lpad((i % 200 + 1)::TEXT, 3, '0'), 'pb-r' || i, '', 'pb-cat' || i % 5, 160
FROM generate_series(1, 20) i
-- level 1: under known and new roots; pb-c1..20 under the deleted pb-r300, so neither
-- they nor pb-cc1..20 and pb-ccc1..20 under them ever resolve
UNION ALL
SELECT 'pb-a' || lpad((i * 7 % 200 + 1)::TEXT, 3, '0'), 'pb-c' || i,
  'pb-a' || lpad(CASE WHEN i <= 20 THEN 300 % 200 + 1 WHEN i % 2 = 0 THEN (i % 299 + 1) % 200 + 1 ELSE i % 1000 % 200 + 1 END::TEXT, 3, '0'),
  CASE WHEN i <= 20 THEN 'pb-r300' WHEN i % 2 = 0 THEN 'pb-r' || i % 299 + 1 ELSE 'pb-nr' || i % 1000 END,
  130 + i % 40
FROM generate_series(1, 3000) i
-- level 2 and 3
UNION ALL
SELECT 'pb-a' || lpad((i * 11 % 200 + 1)::TEXT, 3, '0'), 'pb-cc' || i,
  'pb-a' || lpad((i * 7 % 200 + 1)::TEXT, 3, '0'), 'pb-c' || i, 140 + i % 30
FROM generate_series(1, 1500) i
UNION ALL
SELECT 'pb-a' || lpad((i * 13 % 200 + 1)::TEXT, 3, '0'), 'pb-ccc' || i,
  'pb-a' || lpad((i * 11 % 200 + 1)::TEXT, 3, '0'), 'pb-cc' || i, 150 + i % 20
FROM generate_series(1, 500) i
-- known comments again, and replies to a post that does not exist
UNION ALL
SELECT 'pb-a' || lpad((i % 200 + 1)::TEXT, 3, '0'), 'pb-oc' || i,
  'pb-a' || lpad((i % 200 + 1)::TEXT, 3, '0'), 'pb-r' || i, 165
FROM generate_series(1, 20) i
UNION ALL
SELECT 'pb-a' || lpad(i::TEXT, 3, '0'), 'pb-m' || i, 'pb-a001', 'pb-missing', 165
FROM generate_series(1, 20) i;

UPDATE pb_ops o SET seq_id = s.seq_id
FROM (SELECT permlink, row_number() OVER (ORDER BY md5(permlink))::INT AS seq_id FROM pb_ops) s
WHERE s.permlink = o.permlink;

INSERT INTO hivemind_app.hive_permlink_data (permlink)
SELECT 'pb-r' || i FROM generate_series(1, 300) i
UNION ALL SELECT 'pb-oc' || i FROM generate_series(1, 20) i
UNION ALL SELECT 'pb-missing'
UNION ALL SELECT permlink FROM pb_ops WHERE permlink NOT LIKE 'pb-r%' AND permlink NOT LIKE 'pb-oc%'
ON CONFLICT DO NOTHING;
INSERT INTO hivemind_app.hive_category_data (category)
SELECT DISTINCT parent_permlink FROM pb_ops WHERE parent_author = ''
UNION SELECT 'pb-cat' || i FROM generate_series(0, 4) i
ON CONFLICT DO NOTHING;

-- Known roots: every 7th muted, in a community by i % 4; root_id 0 or its own id.
INSERT INTO hivemind_app.hive_posts (id, root_id, parent_id, author_id, permlink_id, category_id, community_id,
  created_at, depth, is_muted, muted_reasons, counter_deleted, block_num, block_num_created)
SELECT p.id, CASE WHEN p.i % 2 = 0 THEN p.id ELSE 0 END, 0,
  (SELECT id FROM hivemind_app.hive_accounts WHERE name = 'pb-a' || lpad((p.i % 200 + 1)::TEXT, 3, '0')),
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'pb-r' || p.i),
  (SELECT id FROM hivemind_app.hive_category_data WHERE category = 'pb-cat' || p.i % 5),
  (SELECT id FROM hivemind_app.hive_communities WHERE name = 'hive-41000' || p.i % 4),
  '2016-06-01', 0, p.i % 7 = 0, CASE WHEN p.i % 7 = 0 THEN 1 ELSE 0 END,
  CASE WHEN p.i = 300 THEN 1 ELSE 0 END, 100, 100
FROM (
  SELECT i, nextval(pg_get_serial_sequence('hivemind_app.hive_posts', 'id'))::INT AS id FROM generate_series(1, 300) i
) p;
INSERT INTO hivemind_app.hive_posts (root_id, parent_id, author_id, permlink_id, category_id, community_id,
  created_at, depth, block_num, block_num_created)
SELECT hp.id, hp.id, hp.author_id,
  (SELECT id FROM hivemind_app.hive_permlink_data WHERE permlink = 'pb-oc' || i),
  hp.category_id, hp.community_id, '2016-06-02', 1, 110, 110
FROM generate_series(1, 20) i
JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = 'pb-r' || i
JOIN hivemind_app.hive_posts hp ON hp.permlink_id = hpd.id
ORDER BY i;

SELECT set_config('pb.seq', last_value::TEXT, true) FROM hivemind_app.hive_posts_id_seq \gset ignored_

-- Runs the root batch and the comment waves with the _impl functions, from the same
-- hive_posts id sequence position; returns every result row and the hive_posts rows.
CREATE FUNCTION pg_temp.pb_run(_impl TEXT) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  _results JSONB;
  _wave JSONB;
  _waves INT := 0;
  _done INT[] := '{}';
BEGIN
  PERFORM setval('hivemind_app.hive_posts_id_seq', current_setting('pb.seq')::BIGINT);
  EXECUTE format('SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object(''wave'', 0) ORDER BY r.seq_id) FROM %s($1) r',
                 _impl || 'process_root_posts_batch')
  INTO _results
  USING ARRAY(SELECT ROW(o.seq_id, o.author, o.permlink, '', o.parent_permlink,
                         '2016-07-01'::TIMESTAMP + o.block_num * INTERVAL '3 seconds', 150, o.block_num,
                         ARRAY[]::VARCHAR[])::hivemind_app.hive_post_op_input
              FROM pb_ops o WHERE o.parent_author = '' ORDER BY o.seq_id);
  LOOP
    _waves := _waves + 1;
    EXECUTE format('SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object(''wave'', $2) ORDER BY r.seq_id) FROM %s($1) r',
                   _impl || 'process_comments_batch')
    INTO _wave
    USING ARRAY(SELECT ROW(o.seq_id, o.author, o.permlink, o.parent_author, o.parent_permlink,
                           '2016-07-01'::TIMESTAMP + o.block_num * INTERVAL '3 seconds', 150, o.block_num,
                           ARRAY[]::VARCHAR[])::hivemind_app.hive_post_op_input
                FROM pb_ops o WHERE o.parent_author <> '' AND o.seq_id <> ALL(_done) ORDER BY o.seq_id),
          _waves;
    EXIT WHEN _wave IS NULL;
    _results := _results || _wave;
    _done := _done || ARRAY(SELECT (w->>'seq_id')::INT FROM jsonb_array_elements(_wave) w);
  END LOOP;
  -- Tags of the new posts, then an edit of every post: two tags for even ids, one other
  -- for odd ones, so the edit both deletes and inserts post tags.
  EXECUTE format('SELECT %s($1)', _impl || 'process_tags_batch')
  USING ARRAY(SELECT ROW((r->>'id')::INT, '#Pb-T' || ((r->>'id')::INT * k % 97), TRUE)::hivemind_app.post_tag_input
              FROM jsonb_array_elements(_results) r, generate_series(1, 3) k
              WHERE (r->>'is_new_post')::BOOLEAN);
  EXECUTE format('SELECT %s($1)', _impl || 'process_tags_batch')
  USING ARRAY(SELECT ROW((r->>'id')::INT,
                         CASE WHEN (r->>'id')::INT % 2 = 0 THEN 'pb-t' || ((r->>'id')::INT * k % 97) ELSE 'pb-u' || (r->>'id')::INT % 13 END,
                         FALSE)::hivemind_app.post_tag_input
              FROM jsonb_array_elements(_results) r, generate_series(1, 2) k);
  RETURN jsonb_build_object(
    'results', _results,
    'posts', (SELECT jsonb_agg(jsonb_build_object(
                'id', hp.id, 'root_id', CASE WHEN hp.root_id = 0 AND hp.depth = 0 THEN hp.id ELSE hp.root_id END,
                'parent_id', hp.parent_id, 'author_id', hp.author_id,
                'permlink_id', hp.permlink_id, 'category_id', hp.category_id, 'community_id', hp.community_id,
                'created_at', hp.created_at, 'updated_at', hp.updated_at, 'active', hp.active,
                'payout_at', hp.payout_at, 'cashout_time', hp.cashout_time, 'depth', hp.depth,
                'is_muted', hp.is_muted, 'muted_reasons', hp.muted_reasons, 'is_valid', hp.is_valid,
                'sc_hot', hp.sc_hot, 'sc_trend', hp.sc_trend, 'counter_deleted', hp.counter_deleted,
                'block_num', hp.block_num, 'block_num_created', hp.block_num_created) ORDER BY hp.id)
              FROM hivemind_app.hive_posts hp
              JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
              WHERE hpd.permlink LIKE 'pb-%'),
    'tags', (SELECT jsonb_agg(jsonb_build_array(hpt.post_id, htd.tag) ORDER BY hpt.post_id, htd.tag)
             FROM hivemind_app.hive_post_tags hpt
             JOIN hivemind_app.hive_tag_data htd ON htd.id = hpt.tag_id
             WHERE htd.tag LIKE 'pb-%'),
    'unrooted_new_roots', (SELECT count(*)
              FROM jsonb_array_elements(_results) r
              JOIN hivemind_app.hive_posts hp ON hp.id = (r->>'id')::INT
              WHERE r->>'wave' = '0' AND (r->>'is_new_post')::BOOLEAN AND hp.root_id <> hp.id),
    'seq_after', (SELECT last_value FROM hivemind_app.hive_posts_id_seq));
END
$$;

SAVEPOINT old;
SELECT pg_temp.pb_run('pg_temp.old_') AS old_run \gset
ROLLBACK TO SAVEPOINT old;
SELECT set_config('pb.old', :'old_run', true) \gset ignored_

DO $$
DECLARE
  _old JSONB := current_setting('pb.old')::JSONB;
  _new JSONB := pg_temp.pb_run('hivemind_app.');
  _n INT;
  _key TEXT;
  _first RECORD;
BEGIN
  -- The seeded cases must be reached, or the comparison proves little.
  SELECT count(*) INTO _n FROM jsonb_array_elements(_new->'results') r WHERE r->>'wave' <> '0';
  IF _n <> 5040 - 80 THEN
    RAISE EXCEPTION 'setup: expected % comment results (all but the 80 unresolvable), got %', 5040 - 80, _n;
  END IF;
  IF (SELECT max((r->>'wave')::INT) FROM jsonb_array_elements(_new->'results') r) <> 3 THEN
    RAISE EXCEPTION 'setup: expected the comments to resolve in 3 waves';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(_new->'results') r WHERE NOT (r->>'is_new_post')::BOOLEAN) <> 40 THEN
    RAISE EXCEPTION 'setup: expected 40 known posts (is_new_post false)';
  END IF;
  IF (SELECT count(DISTINCT r->>'muted_reasons') FROM jsonb_array_elements(_new->'results') r) < 4 THEN
    RAISE EXCEPTION 'setup: expected all of no, community, parent and both muted reasons';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(_new->'results') r WHERE r->>'community_id' IS NOT NULL) = 0
     OR (SELECT count(*) FROM jsonb_array_elements(_new->'results') r WHERE r->>'parent_author_id' <> '0') = 0 THEN
    RAISE EXCEPTION 'setup: expected community posts and replies';
  END IF;

  IF (SELECT count(*) FROM jsonb_array_elements(_new->'tags') t WHERE t->>1 LIKE 'pb-u%') = 0
     OR (SELECT count(*) FROM jsonb_array_elements(_new->'tags') t WHERE t->>1 LIKE 'pb-t%') = 0 THEN
    RAISE EXCEPTION 'setup: expected post tags from both tag passes: %', left((_new->'tags')::TEXT, 500);
  END IF;

  IF (_old->>'unrooted_new_roots')::INT = 0 THEN
    RAISE EXCEPTION 'setup: expected the previous root batch to leave root_id = 0 on new roots';
  END IF;
  IF (_new->>'unrooted_new_roots')::INT <> 0 THEN
    RAISE EXCEPTION '% new root posts were inserted with root_id != id', _new->>'unrooted_new_roots';
  END IF;

  FOREACH _key IN ARRAY ARRAY['results', 'posts', 'tags'] LOOP
    IF _new->_key IS DISTINCT FROM _old->_key THEN
      SELECT COALESCE(n.i, o.i) AS i, n.v, o.v AS v_old INTO _first
      FROM jsonb_array_elements(_new->_key) WITH ORDINALITY n (v, i)
      FULL JOIN jsonb_array_elements(_old->_key) WITH ORDINALITY o (v, i) ON o.i = n.i
      WHERE n.v IS DISTINCT FROM o.v
      ORDER BY COALESCE(n.i, o.i) LIMIT 1;
      RAISE EXCEPTION E'% differ from the previous implementation (% vs % rows), first at %:\nnew: %\nold: %',
        _key, jsonb_array_length(_new->_key), jsonb_array_length(_old->_key), _first.i, _first.v, _first.v_old;
    END IF;
  END LOOP;
  IF _new->'seq_after' IS DISTINCT FROM _old->'seq_after' THEN
    RAISE EXCEPTION 'hive_posts id sequence ends at %, previously at %', _new->'seq_after', _old->'seq_after';
  END IF;
END
$$;

ROLLBACK;
