DROP FUNCTION IF EXISTS hivemind_app.prepare_tags;
CREATE OR REPLACE FUNCTION hivemind_app.prepare_tags( in _raw_tags VARCHAR[] )
RETURNS SETOF hivemind_app.hive_tag_data.id%TYPE
LANGUAGE 'plpgsql'
VOLATILE
AS
$function$
DECLARE
   __i INTEGER;
   __tags VARCHAR[];
   __tag VARCHAR;
BEGIN
  FOR __i IN 1 .. ARRAY_UPPER( _raw_tags, 1)
  LOOP
    __tag = CAST( LEFT(LOWER(REGEXP_REPLACE( _raw_tags[ __i ], '[#\s]', '', 'g' )),32) as VARCHAR);
    CONTINUE WHEN __tag = '' OR __tag = ANY(__tags);
    __tags = ARRAY_APPEND( __tags, __tag );
  END LOOP;

  RETURN QUERY INSERT INTO
     hivemind_app.hive_tag_data AS htd(tag)
  SELECT UNNEST( __tags )
  ON CONFLICT("tag") DO UPDATE SET tag=EXCLUDED.tag --trick to always return id
  RETURNING htd.id;
END
$function$;

DROP FUNCTION IF EXISTS hivemind_app.encode_bitwise_mask;
CREATE OR REPLACE FUNCTION hivemind_app.encode_bitwise_mask(post_muted_reasons INT[])
    RETURNS INT AS $$
DECLARE
    mask INT := 0;
    number INT;
BEGIN
    FOREACH number IN ARRAY post_muted_reasons
        LOOP
            mask := mask | (1 << number);
        END LOOP;
    RETURN mask;
END;
$$ LANGUAGE plpgsql;

DROP TYPE IF EXISTS hivemind_app.process_community_post_result CASCADE;
CREATE TYPE hivemind_app.process_community_post_result AS (
    is_post_muted bool,
    community_id integer, -- hivemind_app.hive_posts.community_id%TYPE
    post_muted_reasons INTEGER
);

DROP FUNCTION IF EXISTS hivemind_app.process_community_post;
CREATE OR REPLACE FUNCTION hivemind_app.process_community_post(_block_num hivemind_app.hive_posts.block_num%TYPE, _community_support_start_block hivemind_app.hive_posts.block_num%TYPE, _parent_permlink hivemind_app.hive_permlink_data.permlink%TYPE, _author_id hivemind_app.hive_posts.author_id%TYPE, _is_comment bool, _is_parent_post_muted bool, _community_id hivemind_app.hive_posts.community_id%TYPE)
RETURNS hivemind_app.process_community_post_result
LANGUAGE plpgsql
as
    $$
declare
        __community_type_id SMALLINT;
        __role_id SMALLINT;
        __member_role CONSTANT SMALLINT := 2;
        __community_type_topic CONSTANT SMALLINT := 1;
        __community_type_journal CONSTANT SMALLINT := 2;
        __community_type_council CONSTANT SMALLINT := 3;
        __is_post_muted BOOL := TRUE;
        __community_id hivemind_app.hive_posts.community_id%TYPE;
        __post_muted_reasons INTEGER[] := ARRAY[]::INTEGER[];
BEGIN
        IF _block_num < _community_support_start_block THEN
            __is_post_muted := FALSE;
            __community_id := NULL;
        ELSE
            IF _is_comment = TRUE THEN
                SELECT type_id, id INTO __community_type_id, __community_id from hivemind_app.hive_communities where id = _community_id;
            ELSE
                SELECT type_id, id INTO __community_type_id, __community_id from hivemind_app.hive_communities where name = _parent_permlink;
            END IF;

            IF __community_id IS NOT NULL THEN
                IF __community_type_id = __community_type_topic THEN
                    __is_post_muted := FALSE;
                ELSE
                    IF __community_type_id = __community_type_journal AND _is_comment = TRUE THEN
                        __is_post_muted := FALSE;
                    ELSE
                        select role_id into __role_id from hivemind_app.hive_roles where hivemind_app.hive_roles.community_id = __community_id AND account_id = _author_id;
                        IF __community_type_id = __community_type_journal AND _is_comment = FALSE AND __role_id IS NOT NULL AND __role_id >= __member_role THEN
                            __is_post_muted := FALSE;
                        ELSIF __community_type_id = __community_type_council AND __role_id IS NOT NULL AND __role_id >= __member_role THEN
                            __is_post_muted := FALSE;
                        ELSE
                            -- This means the post was muted because of community reasons, 1 is MUTED_COMMUNITY_TYPE see community.py for the ENUM definition
                            __post_muted_reasons := ARRAY[1];
                        END IF;
                    END IF;
                END IF;
            ELSE
                __is_post_muted := FALSE;
            END IF;

            -- __is_post_muted can be TRUE here if it's a comment and its parent is muted
            IF _is_parent_post_muted = TRUE THEN
                __is_post_muted := TRUE;
                -- 2 is MUTED_PARENT, see community.py for the ENUM definition
                __post_muted_reasons := array_append(__post_muted_reasons, 2);
            END IF;

        END IF;

        RETURN (__is_post_muted, __community_id, hivemind_app.encode_bitwise_mask(__post_muted_reasons))::hivemind_app.process_community_post_result;
    END;
$$ STABLE;

DROP FUNCTION IF EXISTS hivemind_app.process_hive_post_operation;
;
CREATE OR REPLACE FUNCTION hivemind_app.process_hive_post_operation(
    in _author hivemind_app.hive_accounts.name%TYPE,
    in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
    in _parent_author hivemind_app.hive_accounts.name%TYPE,
    in _parent_permlink hivemind_app.hive_permlink_data.permlink%TYPE,
    in _date hivemind_app.hive_posts.created_at%TYPE,
    in _community_support_start_block hivemind_app.hive_posts.block_num%TYPE,
    in _block_num hivemind_app.hive_posts.block_num%TYPE,
    in _metadata_tags VARCHAR[])
    RETURNS TABLE (is_new_post boolean, id hivemind_app.hive_posts.id%TYPE, author_id hivemind_app.hive_posts.author_id%TYPE, permlink_id hivemind_app.hive_posts.permlink_id%TYPE,
                   post_category hivemind_app.hive_category_data.category%TYPE, parent_id hivemind_app.hive_posts.parent_id%TYPE, parent_author_id hivemind_app.hive_posts.author_id%TYPE, community_id hivemind_app.hive_posts.community_id%TYPE,
                   is_valid hivemind_app.hive_posts.is_valid%TYPE, is_post_muted hivemind_app.hive_posts.is_muted%TYPE, depth hivemind_app.hive_posts.depth%TYPE, muted_reasons hivemind_app.hive_posts.muted_reasons%TYPE)
    LANGUAGE plpgsql
AS
$function$
BEGIN

    INSERT INTO hivemind_app.hive_permlink_data
    (permlink)
    values
        (
            _permlink
        )
    ON CONFLICT DO NOTHING
    ;
    IF _parent_author != '' THEN
      RETURN QUERY
        WITH selected_posts AS (
          SELECT
            s.parent_id,
            s.parent_author_id,
            s.depth,
            (s.composite).community_id,
            s.category_id,
            s.root_id,
            (s.composite).is_post_muted,
            s.is_valid,
            s.author_id,
            s.permlink_id,
            s.created_at,
            s.updated_at,
            s.sc_hot,
            s.sc_trend,
            s.active,
            s.payout_at,
            s.cashout_time,
            s.counter_deleted,
            s.block_num,
            s.block_num_created,
            (s.composite).post_muted_reasons
          FROM (
            SELECT
                hivemind_app.process_community_post(_block_num, _community_support_start_block, _parent_permlink, ha.id, TRUE, php.is_muted, php.community_id) as composite,
                php.id AS parent_id,
                php.author_id AS parent_author_id,
                php.depth + 1 AS depth,
                COALESCE(php.category_id, (select hcg.id from hivemind_app.hive_category_data hcg where hcg.category = _parent_permlink)) AS category_id,
                (CASE(php.root_id)
                     WHEN 0 THEN php.id
                     ELSE php.root_id
                    END) AS root_id,
                php.is_valid AS is_valid,
                ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
                _date AS updated_at,
                hivemind_app.calculate_time_part_of_hot(_date) AS sc_hot,
                hivemind_app.calculate_time_part_of_trending(_date) AS sc_trend,
                _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time,
                0 AS counter_deleted,
                _block_num as block_num, _block_num as block_num_created
            FROM hivemind_app.hive_accounts ha,
                 hivemind_app.hive_permlink_data hpd,
                 hivemind_app.hive_posts php
                     INNER JOIN hivemind_app.hive_accounts pha ON pha.id = php.author_id
                     INNER JOIN hivemind_app.hive_permlink_data phpd ON phpd.id = php.permlink_id
            WHERE pha.name = _parent_author AND phpd.permlink = _parent_permlink AND
                ha.name = _author AND hpd.permlink = _permlink AND php.counter_deleted = 0
          ) AS s
        ), inserted_post AS (
        INSERT INTO hivemind_app.hive_posts as hp
            (parent_id, depth, community_id, category_id,
             root_id, is_muted, is_valid,
             author_id, permlink_id, created_at, updated_at, active, payout_at, cashout_time, counter_deleted, block_num, block_num_created, muted_reasons)
          SELECT
            s.parent_id,
            s.depth,
            s.community_id,
            s.category_id,
            s.root_id,
            s.is_post_muted,
            s.is_valid,
            s.author_id,
            s.permlink_id,
            s.created_at,
            s.updated_at,
            s.active,
            s.payout_at,
            s.cashout_time,
            s.counter_deleted,
            s.block_num,
            s.block_num_created,
            s.post_muted_reasons
          FROM selected_posts AS s
            ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
                --- During post update it is disallowed to change: parent-post, category, community-id
                --- then also depth, is_valid and is_post_muted is impossible to change
                --- post edit part
                updated_at = _date,
                active = _date,
                block_num = _block_num
          RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, (SELECT hcd.category FROM hivemind_app.hive_category_data hcd WHERE hcd.id = hp.category_id) as post_category, hp.parent_id, (SELECT s.parent_author_id FROM selected_posts AS s) AS parent_author_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth, hp.muted_reasons
         ), rshares_insert AS (
             INSERT INTO hivemind_app.hive_posts_rshares as hpr (post_id, sc_hot, sc_trend)
             SELECT ip.id, s.sc_hot, s.sc_trend
             FROM inserted_post as ip, selected_posts as s
             ON CONFLICT (post_id) DO UPDATE SET
                 sc_hot = EXCLUDED.sc_hot,
                 sc_trend = EXCLUDED.sc_trend
             RETURNING post_id
         )
         SELECT ip.is_new_post, ip.id, ip.author_id, ip.permlink_id, ip.post_category, ip.parent_id, ip.parent_author_id, ip.community_id, ip.is_valid, ip.is_muted, ip.depth, ip.muted_reasons
         FROM inserted_post ip
         LEFT JOIN rshares_insert as ri ON ri.post_id = 0 -- force execute the rshares_insert CTE
        ;
    ELSE
        INSERT INTO hivemind_app.hive_category_data
        (category)
        VALUES (_parent_permlink)
        ON CONFLICT (category) DO NOTHING
        ;

        RETURN QUERY
            WITH posts_data_to_insert AS MATERIALIZED (
                SELECT
                    s.parent_id,
                    s.depth,
                    (s.composite).community_id,
                    s.category_id,
                    s.root_id,
                    (s.composite).is_post_muted,
                    s.is_valid,
                    s.author_id,
                    s.permlink_id,
                    s.created_at,
                    s.updated_at,
                    s.sc_hot,
                    s.sc_trend,
                    s.active,
                    s.payout_at,
                    s.cashout_time,
                    s.counter_deleted,
                    s.block_num,
                    s.block_num_created,
                    (s.composite).post_muted_reasons
                FROM (
                         SELECT
                             hivemind_app.process_community_post(_block_num, _community_support_start_block, _parent_permlink, ha.id, FALSE,FALSE, NULL) as composite,
                             0 AS parent_id, 0 AS depth,
                             (SELECT hcg.id FROM hivemind_app.hive_category_data hcg WHERE hcg.category = _parent_permlink) AS category_id,
                             0 as root_id, -- will use id as root one if no parent
                             true AS is_valid,
                             ha.id AS author_id, hpd.id AS permlink_id, _date AS created_at,
                             _date AS updated_at,
                             hivemind_app.calculate_time_part_of_hot(_date) AS sc_hot,
                             hivemind_app.calculate_time_part_of_trending(_date) AS sc_trend,
                             _date AS active, (_date + INTERVAL '7 days') AS payout_at, (_date + INTERVAL '7 days') AS cashout_time,
                             0 AS counter_deleted,
                             _block_num as block_num, _block_num as block_num_created
                         FROM
                             hivemind_app.hive_accounts ha,
                             hivemind_app.hive_permlink_data hpd
                         WHERE ha.name = _author and hpd.permlink = _permlink
                     ) s
            ), -- posts_data_to_insert
                inserted_post AS MATERIALIZED (
                    INSERT INTO hivemind_app.hive_posts as hp
                        (parent_id, depth, community_id, category_id,
                         root_id, is_muted, is_valid,
                         author_id, permlink_id, created_at, updated_at,
                         active, payout_at, cashout_time, counter_deleted, block_num, block_num_created, muted_reasons) -- removed tagsids
                        SELECT
                            pdi.parent_id,
                            pdi.depth,
                            pdi.community_id,
                            pdi.category_id,
                            pdi.root_id,
                            pdi.is_post_muted,
                            pdi.is_valid,
                            pdi.author_id,
                            pdi.permlink_id,
                            pdi.created_at,
                            pdi.updated_at,
                            pdi.active,
                            pdi.payout_at,
                            pdi.cashout_time,
                            pdi.counter_deleted,
                            pdi.block_num,
                            pdi.block_num_created,
                            pdi.post_muted_reasons
                        FROM posts_data_to_insert as pdi
                        ON CONFLICT ON CONSTRAINT hive_posts_ux1 DO UPDATE SET
                            --- During post update it is disallowed to change: parent-post, category, community-id
                            --- then also depth, is_valid and is_post_muted is impossible to change
                            --- post edit part
                            updated_at = _date,
                            active = _date,
                            block_num = _block_num
                        RETURNING (xmax = 0) as is_new_post, hp.id, hp.author_id, hp.permlink_id, _parent_permlink as post_category, hp.parent_id, hp.community_id, hp.is_valid, hp.is_muted, hp.depth, hp.muted_reasons
                ) -- WITH inserted_post
            , tagsid_and_posts AS MATERIALIZED (
                SELECT prepare_tags FROM hivemind_app.prepare_tags( ARRAY_APPEND(_metadata_tags, _parent_permlink ) )
            ) -- WITH tagsid_and_posts
               , deleted_post_tags AS MATERIALIZED (
                DELETE FROM hivemind_app.hive_post_tags hp
                    USING hivemind_app.hive_post_tags as hpt
                    JOIN inserted_post as ip ON hpt.post_id = ip.id AND NOT ip.is_new_post
                    LEFT JOIN tagsid_and_posts as tap ON tap.prepare_tags = hpt.tag_id
                    WHERE hpt.post_id = hp.post_id AND tap.prepare_tags IS NULL
                    RETURNING hpt.post_id
            ) -- WITH deleted_post_tags
               , rshares_insert AS (
                INSERT INTO hivemind_app.hive_posts_rshares as hpr (post_id, sc_hot, sc_trend)
                SELECT ip.id, pdi.sc_hot, pdi.sc_trend
                FROM inserted_post as ip, posts_data_to_insert as pdi
                ON CONFLICT (post_id) DO UPDATE SET
                    sc_hot = EXCLUDED.sc_hot,
                    sc_trend = EXCLUDED.sc_trend
                RETURNING post_id
            ) -- WITH rshares_insert
               , inserts_to_posts_and_tags AS MATERIALIZED (
                INSERT INTO hivemind_app.hive_post_tags(post_id, tag_id)
                    SELECT ip.id, tags.prepare_tags
                    FROM inserted_post as ip
                    LEFT JOIN deleted_post_tags as dpt ON dpt.post_id = 0 -- there is no post 0, this is only to force execute the deleted_post_tags CTE
                    LEFT JOIN rshares_insert as ri ON ri.post_id = 0 -- force execute the rshares_insert CTE
                    JOIN tagsid_and_posts as tags ON TRUE
                ON CONFLICT DO NOTHING
            )
            SELECT
                ip.is_new_post,
                ip.id,
                ip.author_id,
                ip.permlink_id,
                ip.post_category,
                ip.parent_id,
                0 AS parent_author_id,
                ip.community_id,
                ip.is_valid,
                ip.is_muted,
                ip.depth,
                ip.muted_reasons
            FROM inserted_post as ip;
    END IF;
END
$function$
;

DROP TYPE IF EXISTS hivemind_app.hive_post_op_input CASCADE;
CREATE TYPE hivemind_app.hive_post_op_input AS (
    seq_id INTEGER,
    author VARCHAR,
    permlink VARCHAR,
    parent_author VARCHAR,
    parent_permlink VARCHAR,
    date TIMESTAMP,
    community_support_start_block INTEGER,
    block_num INTEGER,
    metadata_tags VARCHAR[]
);

DROP TYPE IF EXISTS hivemind_app.hive_post_op_result CASCADE;
CREATE TYPE hivemind_app.hive_post_op_result AS (
    seq_id INTEGER,
    is_new_post BOOLEAN,
    id INTEGER,
    author_id INTEGER,
    permlink_id INTEGER,
    post_category VARCHAR,
    parent_id INTEGER,
    parent_author_id INTEGER,
    community_id INTEGER,
    is_valid BOOLEAN,
    is_post_muted BOOLEAN,
    depth SMALLINT,
    muted_reasons INTEGER
);

DROP FUNCTION IF EXISTS hivemind_app.process_hive_post_operations_batch;
CREATE OR REPLACE FUNCTION hivemind_app.process_hive_post_operations_batch(
    _ops hivemind_app.hive_post_op_input[]
)
RETURNS SETOF hivemind_app.hive_post_op_result
LANGUAGE plpgsql
AS
$function$
DECLARE
    _op hivemind_app.hive_post_op_input;
    _row RECORD;
BEGIN
    FOREACH _op IN ARRAY _ops
    LOOP
        FOR _row IN
            SELECT * FROM hivemind_app.process_hive_post_operation(
                _op.author, _op.permlink, _op.parent_author, _op.parent_permlink,
                _op.date, _op.community_support_start_block, _op.block_num, _op.metadata_tags
            )
        LOOP
            RETURN NEXT ROW(
                _op.seq_id, _row.is_new_post, _row.id, _row.author_id, _row.permlink_id,
                _row.post_category, _row.parent_id, _row.parent_author_id, _row.community_id,
                _row.is_valid, _row.is_post_muted, _row.depth, _row.muted_reasons
            )::hivemind_app.hive_post_op_result;
        END LOOP;
    END LOOP;
END
$function$;

--- Set-based batch functions for root posts, comments, and tags.
--- These replace the FOREACH loop in process_hive_post_operations_batch
--- with true set operations for better performance during massive sync.

DROP FUNCTION IF EXISTS hivemind_app.process_root_posts_batch;
CREATE OR REPLACE FUNCTION hivemind_app.process_root_posts_batch(
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

--- Batch prepare tags for multiple posts at once.
--- Accepts a flat list of (post_id, raw_tag, is_new_post) tuples.
--- Normalizes tags, inserts into hive_tag_data, then batch-inserts hive_post_tags
--- and batch-deletes removed tags for edits.
DROP TYPE IF EXISTS hivemind_app.post_tag_input CASCADE;
CREATE TYPE hivemind_app.post_tag_input AS (
    post_id INTEGER,
    raw_tag VARCHAR,
    is_new_post BOOLEAN
);

DROP FUNCTION IF EXISTS hivemind_app.process_tags_batch;
CREATE OR REPLACE FUNCTION hivemind_app.process_tags_batch(
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

--- Set-based comment processing with parent lookup via INNER JOIN.
--- Comments whose parents don't exist yet are silently skipped (INNER JOIN
--- filters them out), allowing wave-based resolution from the Python caller.
DROP FUNCTION IF EXISTS hivemind_app.process_comments_batch;
CREATE OR REPLACE FUNCTION hivemind_app.process_comments_batch(
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

DROP FUNCTION IF EXISTS hivemind_app.process_hive_post_mentions;
CREATE OR REPLACE FUNCTION hivemind_app.process_hive_post_mentions(_post_ids INTEGER[])
RETURNS SETOF BIGINT
LANGUAGE plpgsql
AS
$function$
BEGIN
  -- With clause is inlined, modified call to reptracker_endpoints.get_account_reputation.
  -- Reputation is multiplied by 7.5 rather than 9 to bring the max value to 100 rather than 115.
  -- In case of reputation being 0, the score is set to 25 rather than 0.
  RETURN query
      WITH mentions AS MATERIALIZED
          (
          SELECT DISTINCT post_id AS post_id, T.author_id, ha.id AS account_id, T.block_num, T.block_num-1 as prev_block
          FROM
              hivemind_app.hive_accounts ha
                  INNER JOIN
              (
                  SELECT T.id AS post_id, LOWER( ( SELECT trim( T.mention::text, '{""}') ) ) AS mention, T.author_id, T.block_num
                  FROM
                      (
                          SELECT
                              hp.id, REGEXP_MATCHES( hpd.body, '(?:^|[^a-zA-Z0-9_!#$%&*@\\/])(?:@)([a-zA-Z0-9\\.-]{1,16}[a-zA-Z0-9])(?![a-z])', 'g') AS mention, hp.author_id, hp.block_num
                          FROM hivemind_app.hive_posts AS hp
                          INNER JOIN hivemind_app.hive_post_data hpd ON hp.id = hpd.id
                          WHERE hp.id = ANY(_post_ids)
                            AND hp.counter_deleted = 0
                      ) AS T
              ) AS T ON ha.name = T.mention
          WHERE ha.id != T.author_id
          ORDER BY T.block_num, ha.id
          ),
          delete_old_mentions AS
              (
              DELETE FROM hivemind_app.hive_mentions hm
                  WHERE post_id = ANY(_post_ids)
                      AND NOT EXISTS (
                          SELECT 1 FROM mentions AS m
                          WHERE m.post_id = hm.post_id AND m.account_id = hm.account_id
                      )
                  RETURNING id
              ),
          insert_mentions AS
              (
              INSERT INTO hivemind_app.hive_mentions(post_id, account_id, block_num)
                  SELECT DISTINCT m.post_id, m.account_id, m.block_num
                  FROM mentions AS m
                  LEFT JOIN delete_old_mentions AS dom ON dom.id = 0 -- force evaluation
                  WHERE NOT EXISTS (
                      SELECT 1 FROM
                      hivemind_app.hive_mentions AS hm
                      WHERE hm.post_id = m.post_id
                        AND hm.account_id = m.account_id
                  )
                  RETURNING id
              ),
          delete_old_cache AS
              (
              DELETE FROM hivemind_app.hive_notification_cache AS hnc
                  WHERE post_id = ANY(_post_ids)
                      AND type_id = 16
                      AND NOT EXISTS (
                          SELECT 1
                          FROM mentions AS m
                          WHERE m.post_id = hnc.post_id
                            AND m.author_id = hnc.src
                            AND m.account_id = hnc.dst
                      )
                  RETURNING id
              ),
          mentions_data AS (
              SELECT
                  hm.*,
                  hb.created_at AS created_at,
                  (ROW_NUMBER() OVER(PARTITION BY hm.block_num ORDER BY hm.block_num ASC))::INTEGER AS counter
              FROM mentions hm
              JOIN hivemind_app.blocks_view AS hb ON hb.num = hm.prev_block
              ),
          author_data AS (
              SELECT DISTINCT
                  hm.author_id,
                  a.haf_id
              FROM mentions_data hm
                       LEFT JOIN hivemind_app.hive_accounts a ON a.id = hm.author_id
              ),
          author_rep AS (
              SELECT
                  ad.author_id,
                  (GREATEST(LOG(10, ABS(nullif(r.reputation, 0))) - 9, 0) *
                   CASE WHEN r.reputation < 0 THEN -1 ELSE 1 END * 7.5 + 25)::INT AS rep
              FROM author_data ad
                       LEFT JOIN reptracker_app.account_reputations r ON r.account_id = ad.haf_id
              )
          INSERT INTO hivemind_app.hive_notification_cache
              (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
              SELECT
                  hivemind_app.notification_id(hm.created_at, 16, hm.counter) AS id,
                  hm.block_num,
                  16,
                  hm.created_at,
                  hm.author_id,
                  hm.account_id,
                  hm.post_id,
                  hm.post_id,
                  COALESCE(rep.rep, 25),
                  '', '', ''
              FROM mentions_data AS hm
              LEFT JOIN author_rep AS rep ON rep.author_id = hm.author_id
              LEFT JOIN insert_mentions AS im ON im.id = 0 -- force evaluation
              LEFT JOIN delete_old_cache AS doc ON doc.id = 0 -- force evaluation
              LEFT JOIN hivemind_app.muted AS m ON m.follower = hm.account_id AND m.following = hm.author_id
              LEFT JOIN hivemind_app.follow_muted AS fm ON fm.follower = hm.account_id
              LEFT JOIN hivemind_app.muted AS mi ON mi.follower = fm.following AND mi.following = hm.author_id
              WHERE hm.block_num > hivemind_app.block_before_irreversible('90 days')
                AND COALESCE(rep.rep, 25) > 0
                AND hm.author_id IS DISTINCT FROM hm.account_id
                AND m.follower IS NULL
                AND mi.following IS NULL
              ORDER BY hm.block_num, created_at, hm.author_id, hm.account_id
              ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING
              RETURNING id;
END;
$function$;

DROP FUNCTION IF EXISTS hivemind_app.delete_hive_post(character varying,character varying,character varying, integer, timestamp)
;
CREATE OR REPLACE FUNCTION hivemind_app.delete_hive_post(
  in _author hivemind_app.hive_accounts.name%TYPE,
  in _permlink hivemind_app.hive_permlink_data.permlink%TYPE,
  in _block_num hivemind_app.blocks_view.num%TYPE,
  in _date hivemind_app.hive_posts.active%TYPE)
RETURNS VOID
LANGUAGE plpgsql
AS
$function$
DECLARE
  __account_id INT;
  __post_id INT;
BEGIN

  __account_id = hivemind_app.find_account_id( _author, False );
  __post_id = hivemind_app.find_comment_id( _author, _permlink, False );

  IF __post_id = 0 THEN
    RETURN;
  END IF;

  UPDATE hivemind_app.hive_posts
  SET counter_deleted =
  (
      SELECT max( hps.counter_deleted ) + 1
      FROM hivemind_app.hive_posts hps
      INNER JOIN hivemind_app.hive_permlink_data hpd ON hps.permlink_id = hpd.id
      WHERE hps.author_id = __account_id AND hpd.permlink = _permlink
  )
  ,block_num = _block_num
  ,active = _date
  WHERE id = __post_id;

  DELETE FROM hivemind_app.hive_reblogs
  WHERE post_id = __post_id;

  DELETE FROM hivemind_app.hive_feed_cache
  WHERE post_id = __post_id AND account_id = __account_id;

  DELETE FROM hivemind_app.hive_post_tags
  WHERE post_id = __post_id;

END
$function$
;

DROP TYPE IF EXISTS hivemind_app.delete_post_input CASCADE;
CREATE TYPE hivemind_app.delete_post_input AS (
    seq_id INTEGER,
    author VARCHAR,
    permlink VARCHAR,
    block_num INTEGER,
    date TIMESTAMP
);

DROP FUNCTION IF EXISTS hivemind_app.delete_hive_posts_batch;
CREATE OR REPLACE FUNCTION hivemind_app.delete_hive_posts_batch(
    _deletes hivemind_app.delete_post_input[]
)
RETURNS TABLE(seq_id INTEGER, author VARCHAR, permlink VARCHAR)
LANGUAGE plpgsql
AS
$function$
DECLARE
    _d hivemind_app.delete_post_input;
    _account_id INT;
    _post_id INT;
BEGIN
    FOREACH _d IN ARRAY _deletes
    LOOP
        _account_id = hivemind_app.find_account_id( _d.author, False );
        _post_id = hivemind_app.find_comment_id( _d.author, _d.permlink, False );

        IF _post_id = 0 THEN
            CONTINUE;
        END IF;

        UPDATE hivemind_app.hive_posts
        SET counter_deleted =
        (
            SELECT max( hps.counter_deleted ) + 1
            FROM hivemind_app.hive_posts hps
            INNER JOIN hivemind_app.hive_permlink_data hpd ON hps.permlink_id = hpd.id
            WHERE hps.author_id = _account_id AND hpd.permlink = _d.permlink
        )
        ,block_num = _d.block_num
        ,active = _d.date
        WHERE id = _post_id;

        DELETE FROM hivemind_app.hive_reblogs
        WHERE post_id = _post_id;

        DELETE FROM hivemind_app.hive_feed_cache
        WHERE post_id = _post_id AND account_id = _account_id;

        DELETE FROM hivemind_app.hive_post_tags
        WHERE post_id = _post_id;

        seq_id := _d.seq_id;
        author := _d.author;
        permlink := _d.permlink;
        RETURN NEXT;
    END LOOP;
END
$function$
;
