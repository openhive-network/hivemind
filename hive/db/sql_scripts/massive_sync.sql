--- Pure SQL Massive Sync Functions for Hivemind ---
--- Replaces the Python dispatch loop with SQL functions that read from a staging table ---

-- ============================================================================
-- 1. Staging Table DDL
-- ============================================================================

-- Sequence for community op notification counter (avoids collisions across ops)
CREATE SEQUENCE IF NOT EXISTS hivemind_app.community_op_counter;

-- Crash recovery: tracks the in-flight batch block range.
-- Written atomically before batch processing starts, deleted after completion.
-- If the process crashes, the entry persists and triggers replay on restart.
-- MUST remain LOGGED (not UNLOGGED) to survive PostgreSQL crash recovery.
CREATE TABLE IF NOT EXISTS hivemind_app._batch_queue (
    first_block INT NOT NULL,
    last_block  INT NOT NULL
);
-- The batch phases that are not idempotent and have committed: a replay reuses them
-- rather than applying their ops a second time (Blocks.process_multi_sql).
--   posts_applied:     the posts phase, its results in _batch_post_results
--   post_data_applied: the post data flush (PostDataCache.flush)
--   follows_applied:   the follows phase, its mute changes in _batch_mute_changes
--   stage_a_applied:   the batch's Stage A (load, accounts and communities, posts, community
--                      post ops), so a replay runs its Stage B only: with pipelined massive
--                      sync the next batch's Stage A may have committed on top of it
--   post_counts_applied: hive_accounts.post_count of the batch's posts (process_post_counts_from_staging)
-- A row per in-flight batch: two while pipelined massive sync runs a batch's Stage B beside
-- the next one's Stage A. The markers are read and set by the batch's first_block.
ALTER TABLE hivemind_app._batch_queue
    ADD COLUMN IF NOT EXISTS posts_applied BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS post_data_applied BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS follows_applied BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS stage_a_applied BOOLEAN NOT NULL DEFAULT FALSE;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute
                   WHERE attrelid = 'hivemind_app._batch_queue'::regclass AND attname = 'post_counts_applied') THEN
        ALTER TABLE hivemind_app._batch_queue ADD COLUMN post_counts_applied BOOLEAN NOT NULL DEFAULT FALSE;
        -- the posts phase kept post_count before
        UPDATE hivemind_app._batch_queue SET post_counts_applied = posts_applied;
    END IF;
END
$$;

-- The last hive_posts id reserved for a comment op (reserve_post_ids). Changed in the
-- transaction of the posts phase that reserves, so a replay of a batch whose posts phase
-- rolled back reserves the same ids again (a sequence would have moved on).
-- MUST remain LOGGED, like _batch_queue.
CREATE TABLE IF NOT EXISTS hivemind_app._post_id_slots (
    last_id INT NOT NULL
);
-- Starts after the ids hive_posts_id_seq handed out
INSERT INTO hivemind_app._post_id_slots (last_id)
SELECT CASE WHEN s.is_called THEN s.last_value ELSE s.last_value - 1 END
FROM hivemind_app.hive_posts_id_seq s
WHERE NOT EXISTS (SELECT 1 FROM hivemind_app._post_id_slots);

-- The muted and follow_muted changes of the last follows phase (process_follows_for_blocks),
-- for the notification writers to filter each notification by the lists as they stood at
-- the end of its block: per pair, a row with block_num 0 holds its state before the
-- phase, and one row per change its state after that change (op_seq orders a block's).
-- A reset of a list is a change of every pair of the follower the phase knows of.
-- MUST remain LOGGED, like _batch_queue: a replay whose follows phase committed keeps them
-- (_batch_queue.follows_applied), as the lists no longer show the state before it.
CREATE TABLE IF NOT EXISTS hivemind_app._batch_mute_changes (
    list        SMALLINT NOT NULL,  -- 1: muted, 2: follow_muted
    follower    INT NOT NULL,
    following   INT NOT NULL,
    block_num   INT NOT NULL,
    op_seq      BIGINT NOT NULL,
    is_set      BOOLEAN NOT NULL
);
CREATE INDEX IF NOT EXISTS _batch_mute_changes_follower_idx
    ON hivemind_app._batch_mute_changes (follower, list, following, block_num, op_seq);
CREATE INDEX IF NOT EXISTS _batch_mute_changes_following_idx
    ON hivemind_app._batch_mute_changes (following, list);

-- The _post_results rows of the in-flight batch's posts phase, committed with it
-- (save_batch_post_results). The columns a replay cannot rebuild from _ops_staging.
-- MUST remain LOGGED, like _batch_queue.
CREATE TABLE IF NOT EXISTS hivemind_app._batch_post_results (
    seq_id      INT NOT NULL,
    post_id     INT,
    is_new_post BOOLEAN,
    author_id   INT,
    permlink_id INT,
    depth       SMALLINT,
    parent_id   INT,
    parent_author_id INT,
    community_id INT,
    is_post_muted BOOLEAN,
    muted_reasons INT
);
-- the batch the rows belong to; rows of a batch no longer in _batch_queue are stale
ALTER TABLE hivemind_app._batch_post_results ADD COLUMN IF NOT EXISTS first_block INT;
UPDATE hivemind_app._batch_post_results
SET first_block = (SELECT min(bq.first_block) FROM hivemind_app._batch_queue bq)
WHERE first_block IS NULL;

-- The post versions the in-flight batch's posts phase deleted (_deleted_posts), committed
-- with it like _batch_post_results.
-- MUST remain LOGGED, like _batch_queue.
CREATE TABLE IF NOT EXISTS hivemind_app._batch_deleted_posts (
    first_block INT NOT NULL,
    post_id     INT NOT NULL,
    author_id   INT NOT NULL
);

CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._ops_staging (
    id          BIGINT NOT NULL,       -- HAF operation ID (ordering)
    block_num   INT NOT NULL,
    block_date  TIMESTAMP NOT NULL,
    op_type_id  SMALLINT NOT NULL,
    val         JSONB                  -- body_value (pre-extracted inner payload)
);

-- Drop indexes if they exist (idempotent)
DROP INDEX IF EXISTS hivemind_app._ops_staging_op_type_id_idx;
DROP INDEX IF EXISTS hivemind_app._ops_staging_block_num_id_idx;

CREATE INDEX _ops_staging_op_type_id_idx ON hivemind_app._ops_staging (op_type_id);
CREATE INDEX _ops_staging_block_num_id_idx ON hivemind_app._ops_staging (block_num, id);
-- Out of autovacuum, like _post_batch: every load analyzes it (op_type_id and block_num),
-- so an automatic analyze adds nothing but a pass over the val JSONB column the loads
-- leave out. reset_staging_tables bounds its dead rows.
ALTER TABLE hivemind_app._ops_staging SET (autovacuum_enabled = false);

-- The next massive batch's operations, loaded by prefetch_ops_staging while the current
-- batch runs, and moved to _ops_staging by load_ops_staging_from_prefetch.
CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._ops_staging_next (LIKE hivemind_app._ops_staging);

-- Persistent unlogged tables for process_posts_from_staging (avoids PL/pgSQL stale OID with temp tables)
DROP TABLE IF EXISTS hivemind_app._comment_staging;
CREATE UNLOGGED TABLE hivemind_app._comment_staging (
    seq_id      INT NOT NULL,
    staging_id  BIGINT NOT NULL,   -- original _ops_staging.id for delete-create cycle detection
    is_first    BOOLEAN NOT NULL,
    block_num   INT NOT NULL,
    block_date  TIMESTAMP NOT NULL,
    author      TEXT,
    permlink    TEXT,
    parent_author TEXT,
    parent_permlink TEXT,
    op_body     JSONB,
    is_replayed BOOLEAN NOT NULL DEFAULT FALSE  -- applied in chain order by Step 7b, not by Steps 4-5
);

-- Pairs whose ops process_posts_from_staging applies in chain order (Step 7b) rather
-- than set-based: every comment op from replay_from on and every effective delete.
-- replay_from is NULL for a pair only its deletes are replayed for (the parent of a
-- replayed op, so that it is deleted after its reply is created).
DROP TABLE IF EXISTS hivemind_app._replay_pairs;
CREATE UNLOGGED TABLE hivemind_app._replay_pairs (
    author      TEXT NOT NULL,
    permlink    TEXT NOT NULL,
    replay_from BIGINT,
    PRIMARY KEY (author, permlink)
);

CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._post_results (
    seq_id      INT,
    post_id     INT,
    is_new_post BOOLEAN,
    author_id   INT,
    permlink_id INT,
    depth       SMALLINT,
    parent_id   INT,
    parent_author_id INT,
    community_id INT,
    is_post_muted BOOLEAN,
    muted_reasons INT,
    block_num   INT,
    block_date  TIMESTAMP,
    op_body     JSONB
);

-- The post versions process_posts_from_staging deleted: Stage B removes their reblogs and
-- feed cache rows and takes them off their authors' post_count.
CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._deleted_posts (
    post_id     INT NOT NULL,
    author_id   INT NOT NULL
);

-- Indexes on persistent staging tables for wave loop performance
DROP INDEX IF EXISTS hivemind_app._post_results_seq_id_idx;
CREATE INDEX _post_results_seq_id_idx ON hivemind_app._post_results (seq_id);

DROP INDEX IF EXISTS hivemind_app._comment_staging_author_permlink_idx;
CREATE INDEX _comment_staging_author_permlink_idx ON hivemind_app._comment_staging (author, permlink);

-- Resolved hive_posts rows of one process_root_posts_batch / process_comments_batch call.
-- The result rows are rebuilt by joining the insert's RETURNING to this table on its
-- index: joined to a CTE instead, both sides are estimated at 1 row and the join is
-- planned as a nested loop of two CTE scans, quadratic in the wave size.
DROP TABLE IF EXISTS hivemind_app._post_batch;
CREATE UNLOGGED TABLE hivemind_app._post_batch (
    seq_id           INT NOT NULL,
    author_id        INT NOT NULL,
    permlink_id      INT NOT NULL,
    parent_id        INT,
    parent_author_id INT,
    depth            INT,
    category_id      INT,
    root_id          INT,
    community_id     INT,
    is_valid         BOOLEAN,
    is_muted         BOOLEAN,
    muted_reasons    INT,
    date             TIMESTAMP,
    block_num        INT,
    parent_permlink  VARCHAR
);
CREATE INDEX _post_batch_author_permlink_idx ON hivemind_app._post_batch (author_id, permlink_id);
-- Out of autovacuum: a vacuum between calls finds one small wave's rows in the pages
-- earlier waves left and records a near-zero density, so a later fill of thousands of
-- rows is estimated at a few, and process_root_posts_batch/process_comments_batch join
-- their hive_posts insert's RETURNING to it as a nested loop that reads the whole table
-- per inserted row. Unvacuumed, its reltuples stays unknown (-1, the planner sizes it by
-- its current pages) or holds the last ANALYZE of a call of staging_analyze_min_rows()
-- rows or more, and since the table never shrinks between truncations either estimate is
-- at least the rows a smaller wave loads. reset_staging_tables bounds its dead rows.
ALTER TABLE hivemind_app._post_batch SET (autovacuum_enabled = false);


-- Persistent staging table for vote batch processing (avoids per-call CREATE TEMP TABLE overhead):
-- one row per (voter, author, permlink, block)
DROP TABLE IF EXISTS hivemind_app._vote_batch;
CREATE UNLOGGED TABLE hivemind_app._vote_batch (
    voter       TEXT,
    voter_id    INT,
    author      TEXT,
    author_id   INT,
    permlink    TEXT,
    vote_percent INT,
    last_update TIMESTAMP,
    weight      NUMERIC,
    rshares     BIGINT,
    is_effective BOOLEAN,
    ecv_count   INT,
    block_num   INT,
    ord         BIGINT NOT NULL   -- the order hive_votes ids are drawn in
);
-- Out of autovacuum, like _post_batch: an analyze between calls records some earlier
-- fill (or none), and prepare_votes_from_staging joins the refilled table to the
-- versions of its voted posts, a CTE with no index, as a nested loop that rescans the
-- CTE per vote. Its estimates come from its current pages (reltuples -1, after creation
-- or reset_staging_tables' TRUNCATE) or from prepare_votes_from_staging's own ANALYZE.
ALTER TABLE hivemind_app._vote_batch SET (autovacuum_enabled = false);

-- hive_votes rows of a vote batch, ids already drawn (prepare_votes_from_staging),
-- read by the upsert workers (upsert_votes_partition)
DROP TABLE IF EXISTS hivemind_app._vote_upsert;
CREATE UNLOGGED TABLE hivemind_app._vote_upsert (
    id          BIGINT NOT NULL,
    post_id     INT NOT NULL,
    voter_id    INT NOT NULL,
    author_id   INT NOT NULL,
    permlink_id INT NOT NULL,
    weight      NUMERIC,
    rshares     BIGINT,
    vote_percent INT,
    last_update TIMESTAMP,
    num_changes INT,
    block_num   INT,
    is_effective BOOLEAN,          -- some block of the batch holds an effective vote
    first_is_effective BOOLEAN     -- the batch's first block of this vote does
);
-- Out of autovacuum with _vote_batch, filled with it every call: sized by its current
-- pages, never by an analyze of an earlier batch's rows.
ALTER TABLE hivemind_app._vote_upsert SET (autovacuum_enabled = false);

-- Persistent staging tables for reblog processing
DROP TABLE IF EXISTS hivemind_app._reblog_final;
DROP TABLE IF EXISTS hivemind_app._reblog_ops;
CREATE UNLOGGED TABLE hivemind_app._reblog_ops (
    id           BIGINT,
    block_num    INT,
    block_date   TIMESTAMP,
    auth_account TEXT,
    account      TEXT,
    author       TEXT,
    permlink     TEXT,
    is_delete    BOOLEAN
);
CREATE UNLOGGED TABLE hivemind_app._reblog_final (
    id           BIGINT,
    account      TEXT,
    author       TEXT,
    permlink     TEXT,
    block_date   TIMESTAMP,
    block_num    INT,
    is_delete    BOOLEAN
);

-- Staging table for follow notification events (populated by process_follows_for_blocks,
-- read by flush_follow_notifications_for_blocks). Tracks individual follow events
-- including re-follows after unfollow, which the follows table (final state) doesn't preserve.
CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._follow_notification_events (
    follower_name TEXT NOT NULL,
    following_name TEXT NOT NULL,
    block_num     INT NOT NULL,
    op_seq        BIGINT NOT NULL
);

-- The functions below clear their staging tables with DELETE, not TRUNCATE. A TRUNCATE
-- gives the table a new relfilenode, and dropping the old one's buffers scans the whole
-- buffer pool (once per committing transaction, and once per relation for a table
-- truncated again in the same transaction): a fixed cost per call that grows with
-- shared_buffers, against a few thousand rows to delete. The dead rows are bounded by
-- this reset, which truncates every staging table in one statement, so one scan, every
-- few batches (Blocks._reset_staging_tables_if_due).
CREATE OR REPLACE FUNCTION hivemind_app.reset_staging_tables()
RETURNS VOID AS $function$
BEGIN
    TRUNCATE hivemind_app._ops_staging,
             hivemind_app._follow_notification_events,
             hivemind_app._comment_staging,
             hivemind_app._replay_pairs,
             hivemind_app._post_results,
             hivemind_app._deleted_posts,
             hivemind_app._post_batch,
             hivemind_app._vote_batch,
             hivemind_app._vote_upsert,
             hivemind_app._reblog_ops,
             hivemind_app._reblog_final;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- reset_staging_tables split per stage, for pipelined massive sync: each stage truncates
-- its own tables between two of its batches, never waiting on or blocking the other
-- stage's statements. Stage B's include the handoff tables (set_stage_b_handoff).
CREATE OR REPLACE FUNCTION hivemind_app.reset_stage_a_staging_tables()
RETURNS VOID AS $function$
BEGIN
    TRUNCATE hivemind_app._ops_staging,
             hivemind_app._comment_staging,
             hivemind_app._replay_pairs,
             hivemind_app._post_results,
             hivemind_app._deleted_posts,
             hivemind_app._post_batch;
END
$function$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION hivemind_app.reset_stage_b_staging_tables()
RETURNS VOID AS $function$
BEGIN
    TRUNCATE hivemind_app._ops_staging_b,
             hivemind_app._post_results_b,
             hivemind_app._deleted_posts_b,
             hivemind_app._follow_notification_events,
             hivemind_app._vote_batch,
             hivemind_app._vote_upsert,
             hivemind_app._reblog_ops,
             hivemind_app._reblog_final;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- What Stage B reads of a batch that Stage A wrote: its operations (_ops_staging_b), its
-- posts phase's results (_post_results_b) and the post versions that phase deleted
-- (_deleted_posts_b). With _tables false they are views of Stage A's tables, for a sync
-- that runs the stages of a batch one after the other (live sync, massive sync by
-- default): Stage B reads the tables Stage A has just filled, planned as those tables.
-- With _tables true they are tables of their own, which hand_off_to_stage_b fills, so
-- that pipelined massive sync runs Stage B of a batch while Stage A of the next one
-- refills Stage A's tables. Out of autovacuum, like _ops_staging: reset_stage_b_staging_tables
-- bounds their dead rows.
CREATE OR REPLACE FUNCTION hivemind_app.set_stage_b_handoff(_tables BOOLEAN)
RETURNS VOID AS $function$
DECLARE
    _name TEXT;
    _kind "char" := (SELECT c.relkind FROM pg_class c WHERE c.oid = to_regclass('hivemind_app._ops_staging_b'));
    _wanted "char" := CASE WHEN _tables THEN 'r' ELSE 'v' END;
BEGIN
    IF _kind = _wanted THEN
        RETURN;
    END IF;

    FOREACH _name IN ARRAY ARRAY['_ops_staging_b', '_post_results_b', '_deleted_posts_b'] LOOP
        CASE (SELECT c.relkind FROM pg_class c WHERE c.oid = to_regclass(format('hivemind_app.%I', _name)))
            WHEN 'v' THEN EXECUTE format('DROP VIEW hivemind_app.%I', _name);
            WHEN 'r' THEN EXECUTE format('DROP TABLE hivemind_app.%I', _name);
            ELSE NULL;
        END CASE;
    END LOOP;

    IF _tables THEN
        -- hand_off_to_stage_b trades the names of this table and _ops_staging, indexes included
        CREATE UNLOGGED TABLE hivemind_app._ops_staging_b (LIKE hivemind_app._ops_staging);
        CREATE INDEX _ops_staging_b_op_type_id_idx ON hivemind_app._ops_staging_b (op_type_id);
        CREATE INDEX _ops_staging_b_block_num_id_idx ON hivemind_app._ops_staging_b (block_num, id);
        ALTER TABLE hivemind_app._ops_staging_b SET (autovacuum_enabled = false);
        CREATE UNLOGGED TABLE hivemind_app._post_results_b (LIKE hivemind_app._post_results)
            WITH (autovacuum_enabled = false);
        CREATE UNLOGGED TABLE hivemind_app._deleted_posts_b (LIKE hivemind_app._deleted_posts)
            WITH (autovacuum_enabled = false);
    ELSE
        CREATE VIEW hivemind_app._ops_staging_b AS SELECT * FROM hivemind_app._ops_staging;
        CREATE VIEW hivemind_app._post_results_b AS SELECT * FROM hivemind_app._post_results;
        CREATE VIEW hivemind_app._deleted_posts_b AS SELECT * FROM hivemind_app._deleted_posts;
    END IF;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- A fresh install starts with the views; a reinstall keeps what the last sync left.
SELECT hivemind_app.set_stage_b_handoff(FALSE)
WHERE to_regclass('hivemind_app._ops_staging_b') IS NULL;

-- Hands the batch Stage A has just staged to Stage B (set_stage_b_handoff(TRUE)), while
-- neither stage runs a statement. _ops_staging trades names with _ops_staging_b: a copy
-- would cost Stage A another load of the batch's operations, and Stage B then reads the
-- statistics the load analyzed. The posts phase's results are copied without the op bodies,
-- which only Python's body merge reads (it has them from the phase).
CREATE OR REPLACE FUNCTION hivemind_app.hand_off_to_stage_b()
RETURNS VOID AS $function$
BEGIN
    ALTER TABLE hivemind_app._ops_staging RENAME TO _ops_staging_swap;
    ALTER INDEX hivemind_app._ops_staging_op_type_id_idx RENAME TO _ops_staging_swap_op_type_id_idx;
    ALTER INDEX hivemind_app._ops_staging_block_num_id_idx RENAME TO _ops_staging_swap_block_num_id_idx;
    ALTER TABLE hivemind_app._ops_staging_b RENAME TO _ops_staging;
    ALTER INDEX hivemind_app._ops_staging_b_op_type_id_idx RENAME TO _ops_staging_op_type_id_idx;
    ALTER INDEX hivemind_app._ops_staging_b_block_num_id_idx RENAME TO _ops_staging_block_num_id_idx;
    ALTER TABLE hivemind_app._ops_staging_swap RENAME TO _ops_staging_b;
    ALTER INDEX hivemind_app._ops_staging_swap_op_type_id_idx RENAME TO _ops_staging_b_op_type_id_idx;
    ALTER INDEX hivemind_app._ops_staging_swap_block_num_id_idx RENAME TO _ops_staging_b_block_num_id_idx;

    DELETE FROM hivemind_app._post_results_b;
    INSERT INTO hivemind_app._post_results_b
        (seq_id, post_id, is_new_post, author_id, permlink_id, depth, parent_id, parent_author_id,
         community_id, is_post_muted, muted_reasons, block_num, block_date)
    SELECT pr.seq_id, pr.post_id, pr.is_new_post, pr.author_id, pr.permlink_id, pr.depth, pr.parent_id,
           pr.parent_author_id, pr.community_id, pr.is_post_muted, pr.muted_reasons, pr.block_num, pr.block_date
    FROM hivemind_app._post_results pr;

    DELETE FROM hivemind_app._deleted_posts_b;
    INSERT INTO hivemind_app._deleted_posts_b (post_id, author_id)
    SELECT dp.post_id, dp.author_id FROM hivemind_app._deleted_posts dp;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- Helper: safe_parse_jsonb — parse text extracted via ->> back into jsonb
-- ============================================================================
-- The ->> operator resolves JSON escapes (\n → literal newline, \t → literal tab, etc.)
-- but PostgreSQL's ::jsonb parser rejects literal control characters in strings.
-- Re-escape them so the text is valid JSON again.
--
-- Note: \u0000 stripping is no longer needed — HAF now strips null bytes
-- at storage time via strip_json_null_escapes() in the C COPY serializer.
--
-- This is a pure SQL function (no PL/pgSQL EXCEPTION handler) for performance:
-- avoids subtransaction overhead per call (~36% faster in benchmarks).
-- If the input is truly malformed JSON (extremely rare in blockchain data),
-- this will raise an error that propagates to the caller.

CREATE OR REPLACE FUNCTION hivemind_app.safe_parse_jsonb(_text TEXT)
RETURNS JSONB AS $function$
    SELECT CASE WHEN _text IS NULL THEN NULL ELSE
        REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
            _text,
        E'\b', '\b'), E'\f', '\f'), E'\n', '\n'), E'\r', '\r'), E'\t', '\t')::jsonb
    END
$function$ LANGUAGE sql IMMUTABLE;

-- PL/pgSQL version with EXCEPTION handler — returns NULL on malformed JSON.
-- Used in row-by-row loops where individual failures should be skipped.
CREATE OR REPLACE FUNCTION hivemind_app.safe_parse_jsonb_tolerant(_text TEXT)
RETURNS JSONB AS $function$
BEGIN
    IF _text IS NULL THEN RETURN NULL; END IF;
    RETURN REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        _text,
    E'\b', '\b'), E'\f', '\f'), E'\n', '\n'), E'\r', '\r'), E'\t', '\t')::jsonb;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END
$function$ LANGUAGE plpgsql IMMUTABLE;

-- ============================================================================
-- 2. load_ops_staging(_first_block, _last_block)
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.load_ops_staging(
    _first_block INT,
    _last_block INT
) RETURNS VOID AS $function$
BEGIN
    DELETE FROM hivemind_app._ops_staging;

    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    WITH block_dates AS (
        -- Single scan of blocks_view; lag() gives us the previous block's date
        -- without a second join. Include _first_block - 1 so that lag() has a
        -- predecessor for the first block in the range.
        SELECT num, created_at,
               COALESCE(lag(created_at) OVER (ORDER BY num), created_at) AS prev_date
        FROM hivemind_app.blocks_view
        WHERE num BETWEEN (_first_block - 1) AND _last_block
    )
    SELECT ho.id, ho.block_num,
           -- Old Python used _head_block_date (previous block's date) for regular ops,
           -- but the current block's date for virtual ops (payouts processed in _process_vops_flat
           -- received date=block_dates[block_num]). Match that behavior.
           CASE WHEN ho.op_type_id >= 50
               THEN bd.created_at
               ELSE bd.prev_date
           END AS block_date,
           ho.op_type_id, ho.body_value
    FROM hivemind_app.operations_view ho
    JOIN block_dates bd ON bd.num = ho.block_num
    WHERE ho.block_num BETWEEN _first_block AND _last_block
      AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43,51,53,61,72,73)
      AND (ho.op_type_id != 18
        OR ho.custom_json_type_id IN (
            SELECT cjt.id FROM hafd.custom_json_types cjt
            WHERE cjt.custom_json_id IN ('follow', 'reblog', 'community', 'notify')
        ));

    -- Partial ANALYZE: skip the expensive val JSONB column
    ANALYZE hivemind_app._ops_staging (op_type_id, block_num);
END
$function$ LANGUAGE plpgsql VOLATILE;

-- Loads into _ops_staging_next the rows load_ops_staging would load for the blocks of
-- _first_block.._last_block that HAF has made irreversible and consistent, and returns
-- the last block loaded (NULL when none is). Massive sync runs it for the range it
-- expects hive.app_next_iteration to hand out next, before HAF has handed it out: the
-- context's views do not show those blocks yet, so it reads the tables of HAF's
-- non-forking views, bounded by hive_state's consistent block, which is the bound
-- app_next_iteration itself puts on a range. A block at or below it is complete in
-- hafd.blocks and hafd.operations and never changes.
CREATE OR REPLACE FUNCTION hivemind_app.prefetch_ops_staging(
    _first_block INT,
    _last_block INT
) RETURNS INT AS $function$
DECLARE
    _loaded_last INT := LEAST(_last_block, hive.app_get_irreversible_block());
BEGIN
    TRUNCATE hivemind_app._ops_staging_next;
    IF _loaded_last < _first_block THEN
        RETURN NULL;
    END IF;

    -- The query of load_ops_staging, on the tables behind blocks_view and operations_view.
    INSERT INTO hivemind_app._ops_staging_next (id, block_num, block_date, op_type_id, val)
    WITH block_dates AS (
        SELECT hb.num, hb.created_at,
               COALESCE(lag(hb.created_at) OVER (ORDER BY hb.num), hb.created_at) AS prev_date
        FROM hafd.blocks hb
        WHERE hb.num BETWEEN (_first_block - 1) AND _loaded_last
    )
    SELECT ho.id, hafd.operation_id_to_block_num(ho.id),
           CASE WHEN ho.op_type_id >= 50
               THEN bd.created_at
               ELSE bd.prev_date
           END AS block_date,
           ho.op_type_id, ho.body_value
    FROM hafd.operations ho
    JOIN hafd.operation_types ot ON ot.id = ho.op_type_id
    JOIN block_dates bd ON bd.num = hafd.operation_id_to_block_num(ho.id)
    WHERE hafd.operation_id_to_block_num(ho.id) BETWEEN _first_block AND _loaded_last
      AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43,51,53,61,72,73)
      AND (ho.op_type_id != 18
        OR ho.custom_json_type_id IN (
            SELECT cjt.id FROM hafd.custom_json_types cjt
            WHERE cjt.custom_json_id IN ('follow', 'reblog', 'community', 'notify')
        ));

    RETURN _loaded_last;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- load_ops_staging(_first_block, _last_block) from the rows prefetch_ops_staging loaded,
-- which must cover the range.
CREATE OR REPLACE FUNCTION hivemind_app.load_ops_staging_from_prefetch(
    _first_block INT,
    _last_block INT
) RETURNS VOID AS $function$
BEGIN
    DELETE FROM hivemind_app._ops_staging;

    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    SELECT n.id, n.block_num, n.block_date, n.op_type_id, n.val
    FROM hivemind_app._ops_staging_next n
    WHERE n.block_num BETWEEN _first_block AND _last_block
    ORDER BY n.id;

    ANALYZE hivemind_app._ops_staging (op_type_id, block_num);
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 3. process_accounts_from_staging()
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_accounts_from_staging(
    _community_support_start_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    -- Extract account names from account creation ops
    -- Types: 9=ACCOUNT_CREATE, 14=POW, 23=CREATE_CLAIMED_ACCOUNT,
    --        30=POW_2, 41=ACCOUNT_CREATE_WITH_DELEGATION
    WITH new_accounts AS (
        SELECT DISTINCT ON (acct_name)
               acct_name, first_block_date, first_block_num, first_op_id,
               posting_json_metadata, json_metadata
        FROM (
            SELECT
                s.id AS first_op_id,
                CASE s.op_type_id
                    WHEN 9  THEN s.val->>'new_account_name'
                    WHEN 41 THEN s.val->>'new_account_name'
                    WHEN 23 THEN s.val->>'new_account_name'
                    WHEN 14 THEN s.val->>'worker_account'
                    WHEN 30 THEN s.val->'work'->'value'->'input'->>'worker_account'
                END AS acct_name,
                s.block_date AS first_block_date,
                s.block_num AS first_block_num,
                CASE WHEN s.op_type_id IN (9, 41, 23) THEN
                    COALESCE(s.val->>'posting_json_metadata', '')
                ELSE '' END AS posting_json_metadata,
                CASE WHEN s.op_type_id IN (9, 41, 23) THEN
                    COALESCE(s.val->>'json_metadata', '')
                ELSE '' END AS json_metadata
            FROM hivemind_app._ops_staging s
            WHERE s.op_type_id IN (9, 14, 23, 30, 41)
        ) sub
        WHERE acct_name IS NOT NULL
        ORDER BY acct_name, first_op_id
    ),
    -- Only insert accounts that don't already exist
    to_insert AS (
        SELECT na.acct_name, na.first_block_date, na.first_block_num,
               na.first_op_id, na.posting_json_metadata, na.json_metadata
        FROM new_accounts na
        WHERE NOT EXISTS (
            SELECT 1 FROM hivemind_app.hive_accounts ha WHERE ha.name = na.acct_name
        )
    ),
    inserted AS (
        -- An account takes HAF's id; a created account HAF lacks fails the insert on the NOT NULL id
        INSERT INTO hivemind_app.hive_accounts (id, name, created_at, posting_json_metadata, json_metadata)
        SELECT (SELECT av.id FROM hivemind_app.accounts_view av WHERE av.name = ti.acct_name),
               ti.acct_name, ti.first_block_date, ti.posting_json_metadata, ti.json_metadata
        FROM to_insert ti
        ON CONFLICT (name) DO NOTHING
        RETURNING id, name
    )
    SELECT count(*) INTO _count FROM inserted;

    -- Register communities for newly created accounts (if after community start block)
    -- This mirrors the Python Community.register() call
    IF _community_support_start_block > 0 THEN
        PERFORM hivemind_app.process_community_registrations_from_staging(_community_support_start_block);
    END IF;

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- Helper: register communities for new accounts (called from process_accounts_from_staging)
CREATE OR REPLACE FUNCTION hivemind_app.process_community_registrations_from_staging(
    _community_support_start_block INT
) RETURNS VOID AS $function$
DECLARE
    _rec RECORD;
    _counter INT;
BEGIN
    -- For each newly created account matching hive-[123]\d{4,6}$ pattern that was
    -- created at or after the community support start block, register a community.
    -- This mirrors the old Python Community.register() called from Accounts.register().
    FOR _rec IN
        SELECT ha.name, ha.id AS account_id, s.block_date, s.block_num,
               ROW_NUMBER() OVER (PARTITION BY s.block_num ORDER BY s.id)::INT AS counter
        FROM hivemind_app._ops_staging s
        JOIN hivemind_app.hive_accounts ha ON ha.name = CASE s.op_type_id
            WHEN 9  THEN s.val->>'new_account_name'
            WHEN 41 THEN s.val->>'new_account_name'
            WHEN 23 THEN s.val->>'new_account_name'
            WHEN 14 THEN s.val->>'worker_account'
            WHEN 30 THEN s.val->'work'->'value'->'input'->>'worker_account'
        END
        WHERE s.op_type_id IN (9, 14, 23, 30, 41)
          AND s.block_num > _community_support_start_block
          AND ha.name ~ '^hive-[123]\d{4,6}$'
          AND NOT EXISTS (
              SELECT 1 FROM hivemind_app.hive_communities hc WHERE hc.name = ha.name
          )
        ORDER BY s.id
    LOOP
        PERFORM hivemind_app.register_community(
            _rec.name, _rec.account_id, _rec.block_date, _rec.block_num, _rec.counter
        );
    END LOOP;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 4. process_votes_from_staging()
-- ============================================================================

-- Builds the batch's hive_votes rows in _vote_upsert, each with its hive_votes id
-- already drawn. upsert_votes_partition writes them; massive sync runs the
-- partitions on separate connections once this has committed.
--
-- The rows are the ones processing the batch one block at a time would leave: each
-- block's votes of one voter on one post are folded as a one-block batch folds them,
-- each block resolves the post as it is at the end of that block (a post deleted in a
-- later block still takes the vote; a vote cast before a delete and re-create stays
-- with the deleted version), and the blocks are then folded as successive upserts
-- would apply them.
CREATE OR REPLACE FUNCTION hivemind_app.prepare_votes_from_staging()
RETURNS VOID AS $function$
DECLARE
    _vote_rows INT;
    _analyzed_rows INT;
BEGIN
    -- Step 1: One row per (voter, author, permlink, block) from vote ops (type 0) and
    -- effective_comment_vote ops (type 72): the last vote's vote_percent/last_update,
    -- the last effective vote's weight/rshares, and how many effective votes the block
    -- holds. A block without a type 0 op writes vote_percent 0 and last_update
    -- 1970-01-01, as a one-block batch did.
    DELETE FROM hivemind_app._vote_batch;
    INSERT INTO hivemind_app._vote_batch
    WITH vote_ops AS (
        SELECT
            s.id,
            s.block_num,
            s.op_type_id,
            s.block_date,
            s.val->>'voter' AS voter,
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            CASE WHEN s.op_type_id = 0 THEN (s.val->>'weight')::INT END AS vote_percent,
            CASE WHEN s.op_type_id = 72 THEN (s.val->>'weight')::NUMERIC END AS weight,
            CASE WHEN s.op_type_id <> 72 THEN NULL
                WHEN s.block_num < 905693 THEN (s.val->>'rshares')::BIGINT * 1000000
                ELSE (s.val->>'rshares')::BIGINT
            END AS rshares
        FROM hivemind_app._ops_staging_b s
        WHERE s.op_type_id IN (0, 72)
    ),
    block_votes AS (
        SELECT
            voter, author, permlink, block_num,
            COALESCE((array_agg(vote_percent ORDER BY id DESC) FILTER (WHERE op_type_id = 0))[1], 0) AS vote_percent,
            COALESCE((array_agg(block_date ORDER BY id DESC) FILTER (WHERE op_type_id = 0))[1], '1970-01-01'::TIMESTAMP) AS last_update,
            COALESCE((array_agg(weight ORDER BY id DESC) FILTER (WHERE op_type_id = 72))[1], 0) AS weight,
            COALESCE((array_agg(rshares ORDER BY id DESC) FILTER (WHERE op_type_id = 72))[1], 0) AS rshares,
            count(*) FILTER (WHERE op_type_id = 72) AS ecv_count
        FROM vote_ops
        GROUP BY voter, author, permlink, block_num
    ),
    -- Each account name is looked up once, however many votes it casts or receives.
    account_ids AS (
        SELECT ha.name, ha.id
        FROM (
            SELECT voter AS name FROM block_votes
            UNION
            SELECT author FROM block_votes
        ) n
        JOIN hivemind_app.hive_accounts ha ON ha.name = n.name
    )
    SELECT
        bv.voter,
        ha_voter.id AS voter_id,
        bv.author,
        ha_author.id AS author_id,
        bv.permlink,
        bv.vote_percent,
        bv.last_update,
        bv.weight,
        bv.rshares,
        bv.ecv_count > 0 AS is_effective,
        bv.ecv_count::INT AS ecv_count,
        bv.block_num,
        -- ord decides the order hive_votes ids are drawn in (step 2): one voter's
        -- votes on one post share their first row's ord. Block first, as one-block
        -- batches draw them: the ids of any two rows are then in the same order
        -- whatever the batch size, and so are the vote notification counters.
        row_number() OVER (ORDER BY bv.block_num, bv.voter, bv.author, bv.permlink) AS ord
    FROM block_votes bv
    JOIN account_ids ha_voter ON ha_voter.name = bv.voter
    JOIN account_ids ha_author ON ha_author.name = bv.author;

    -- Step 2 is planned from _vote_batch's statistics, which describe the last fill
    -- analyzed; below staging_analyze_min_rows() rows any plan is cheap. A fill within
    -- a factor of 2 of that one is not analyzed again: the planner sizes the table by
    -- its current pages (TRUNCATE leaves reltuples -1, and never clears pg_statistic),
    -- the distinct counts it stores as fractions scale with it, and step 2 keeps the
    -- freshly analyzed plan up to about 8x apart. The count analyzed lives in a session
    -- setting, as a local resets every call: a new connection analyzes its first fill.
    GET DIAGNOSTICS _vote_rows = ROW_COUNT;
    IF _vote_rows >= hivemind_app.staging_analyze_min_rows() THEN
        _analyzed_rows := NULLIF(current_setting('hivemind.vote_batch_analyzed_rows', true), '')::INT;
        IF _analyzed_rows IS NULL OR _vote_rows > 2 * _analyzed_rows OR 2 * _vote_rows < _analyzed_rows THEN
            ANALYZE hivemind_app._vote_batch (voter_id, author_id, permlink, block_num);
            PERFORM set_config('hivemind.vote_batch_analyzed_rows', _vote_rows::TEXT, false);
        END IF;
    END IF;

    -- Step 2: Resolve each block's post, fold the blocks of each voter's vote on a
    -- post, and draw its hive_votes id
    DELETE FROM hivemind_app._vote_upsert;
    WITH pair_version AS MATERIALIZED (
        -- Every version of each voted post, resolved once however many votes hit it.
        -- A deleted version's block_num is the block that deleted it. MATERIALIZED, or
        -- the planner joins it back to the votes first and looks the post up per vote.
        SELECT
            t.author_id,
            t.permlink,
            hpd.id AS permlink_id,
            hp.id AS post_id,
            hp.block_num_created,
            CASE WHEN hp.counter_deleted = 0 THEN NULL ELSE hp.block_num END AS deleted_block
        FROM (
            SELECT DISTINCT author_id, permlink FROM hivemind_app._vote_batch
        ) t
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = t.permlink
        JOIN hivemind_app.hive_posts hp
            ON hp.author_id = t.author_id
            AND hp.permlink_id = hpd.id
    ),
    resolved AS (
        -- The version live at the end of the vote's block; a vote whose block ends
        -- with no live version is dropped, as that block alone would drop it.
        SELECT vb.*, pv.post_id, pv.permlink_id
        FROM hivemind_app._vote_batch vb
        JOIN pair_version pv
            ON pv.author_id = vb.author_id
            AND pv.permlink = vb.permlink
            AND pv.block_num_created <= vb.block_num
            AND (pv.deleted_block IS NULL OR pv.deleted_block > vb.block_num)
    ),
    -- Successive one-block upserts leave the last block's post_id, vote_percent and
    -- last_update, the last effective block's weight and rshares, and count
    -- GREATEST(effective votes, 1) changes per block after the first row's.
    folded AS (
        SELECT
            r.voter_id,
            r.author_id,
            r.permlink_id,
            (array_agg(r.post_id ORDER BY r.block_num DESC))[1] AS post_id,
            (array_agg(r.vote_percent ORDER BY r.block_num DESC))[1] AS vote_percent,
            (array_agg(r.last_update ORDER BY r.block_num DESC))[1] AS last_update,
            COALESCE((array_agg(r.weight ORDER BY r.block_num DESC) FILTER (WHERE r.is_effective))[1], 0) AS weight,
            COALESCE((array_agg(r.rshares ORDER BY r.block_num DESC) FILTER (WHERE r.is_effective))[1], 0) AS rshares,
            bool_or(r.is_effective) AS is_effective,
            (array_agg(r.is_effective ORDER BY r.block_num))[1] AS first_is_effective,
            (sum(GREATEST(r.ecv_count, 1)) - 1)::INT AS num_changes,
            max(r.block_num) AS block_num,
            min(r.ord) AS ord
        FROM resolved r
        GROUP BY r.voter_id, r.author_id, r.permlink_id
    )
    -- One id per row, including the rows that will take the ON CONFLICT path:
    -- the sequence ends where an INSERT drawing the column default would leave it.
    -- Draw ids in ord: vote notification counters follow hive_votes.id.
    INSERT INTO hivemind_app._vote_upsert
        (id, post_id, voter_id, author_id, permlink_id, weight, rshares,
         vote_percent, last_update, num_changes, block_num, is_effective, first_is_effective)
    SELECT
        nextval('hivemind_app.hive_votes_id_seq'),
        f.post_id, f.voter_id, f.author_id, f.permlink_id,
        f.weight, f.rshares, f.vote_percent, f.last_update,
        f.num_changes, f.block_num, f.is_effective, f.first_is_effective
    FROM (SELECT * FROM folded ORDER BY ord) f;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- Upserts the _vote_upsert rows with permlink_id % _parts = _part into hive_votes;
-- returns how many it wrote. The partitions split the hive_votes unique key
-- (voter_id, author_id, permlink_id), so concurrent partitions never touch the same row.
CREATE OR REPLACE FUNCTION hivemind_app.upsert_votes_partition(_part INT, _parts INT)
RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    WITH upserted AS (
        INSERT INTO hivemind_app.hive_votes
            (id, post_id, voter_id, author_id, permlink_id, weight, rshares,
             vote_percent, last_update, num_changes, block_num, is_effective)
        SELECT
            vu.id, vu.post_id, vu.voter_id, vu.author_id, vu.permlink_id,
            vu.weight, vu.rshares, vu.vote_percent, vu.last_update,
            vu.num_changes, vu.block_num, vu.is_effective
        FROM hivemind_app._vote_upsert vu
        WHERE vu.permlink_id % _parts = _part
        ORDER BY vu.id
        ON CONFLICT ON CONSTRAINT hive_votes_voter_id_author_id_permlink_id_uk DO UPDATE SET
            post_id = EXCLUDED.post_id,
            weight = CASE EXCLUDED.is_effective
                WHEN true THEN EXCLUDED.weight
                ELSE hivemind_app.hive_votes.weight END,
            rshares = CASE EXCLUDED.is_effective
                WHEN true THEN EXCLUDED.rshares
                ELSE hivemind_app.hive_votes.rshares END,
            vote_percent = EXCLUDED.vote_percent,
            last_update = EXCLUDED.last_update,
            num_changes = CASE
                WHEN EXCLUDED.block_num <= hivemind_app.hive_votes.block_num
                THEN hivemind_app.hive_votes.num_changes  -- replay: skip increment
                ELSE hivemind_app.hive_votes.num_changes + EXCLUDED.num_changes + 1
            END,
            block_num = GREATEST(EXCLUDED.block_num, hivemind_app.hive_votes.block_num)
        WHERE hivemind_app.hive_votes.voter_id = EXCLUDED.voter_id
          AND hivemind_app.hive_votes.author_id = EXCLUDED.author_id
          AND hivemind_app.hive_votes.permlink_id = EXCLUDED.permlink_id
        RETURNING 1
    )
    SELECT count(*) INTO _count FROM upserted;

    -- EXCLUDED.is_effective says whether the batch brings a weight and rshares; a row
    -- the batch inserts takes is_effective from its first block, as that block's own
    -- insert would. hv.id = vu.id only for a row inserted here: the ON CONFLICT path
    -- keeps the existing row's id.
    UPDATE hivemind_app.hive_votes hv
    SET is_effective = FALSE
    FROM hivemind_app._vote_upsert vu
    WHERE vu.permlink_id % _parts = _part
      AND vu.is_effective AND NOT vu.first_is_effective
      AND hv.voter_id = vu.voter_id
      AND hv.author_id = vu.author_id
      AND hv.permlink_id = vu.permlink_id
      AND hv.id = vu.id;

    -- Rshares aggregates (sc_hot, sc_trend, etc.) are NOT updated per-batch during
    -- massive sync. The key index (hive_votes_post_id_block_num_rshares_vote_is_effective_idx)
    -- is dropped for write performance, making per-batch update_posts_rshares() extremely
    -- expensive. Instead, recalculate_all_posts_votes_and_children() runs once at finalization after
    -- indexes are recreated (see DbState._finish_hive_posts).

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- The whole votes phase on one connection; returns the number of hive_votes rows written.
CREATE OR REPLACE FUNCTION hivemind_app.process_votes_from_staging(
    _last_safe_cashout_block INT DEFAULT 0
) RETURNS INT AS $function$
BEGIN
    PERFORM hivemind_app.prepare_votes_from_staging();
    RETURN hivemind_app.upsert_votes_partition(0, 1);
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 5. process_reblogs_from_staging()
-- ============================================================================

-- A post version is resolved as live at the end of the batch, block _last_block: created by
-- then, and not deleted by then (a deleted version's block_num is the block that deleted
-- it). Pipelined massive sync runs this beside the next batch's posts phase, whose deletes
-- and re-creates this must not see.
DROP FUNCTION IF EXISTS hivemind_app.process_reblogs_from_staging();
CREATE OR REPLACE FUNCTION hivemind_app.process_reblogs_from_staging(_last_block INT)
RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    -- The cascade of the batch's post deletes, before its reblogs as when the posts phase
    -- ran it: the next batch's posts phase, which may run beside this, leaves hive_reblogs
    -- and hive_feed_cache to it.
    DELETE FROM hivemind_app.hive_reblogs
    WHERE post_id IN (SELECT dp.post_id FROM hivemind_app._deleted_posts_b dp);
    DELETE FROM hivemind_app.hive_feed_cache hfc
    USING hivemind_app._deleted_posts_b dp
    WHERE hfc.post_id = dp.post_id AND hfc.account_id = dp.author_id;

    -- Extract reblog custom_json ops from staging (type 18, custom_json_id = 'reblog' or 'follow')
    -- Reblogs come as custom_json with id='follow' or id='reblog' containing ["reblog", {...}]

    DELETE FROM hivemind_app._reblog_ops;
    DELETE FROM hivemind_app._reblog_final;

    INSERT INTO hivemind_app._reblog_ops
    WITH raw_ops AS (
        SELECT
            s.id,
            s.block_num,
            s.block_date,
            s.val AS val
        FROM hivemind_app._ops_staging_b s
        WHERE s.op_type_id = 18
    ),
    parsed AS (
        SELECT
            ro.id,
            ro.block_num,
            ro.block_date,
            ro.val,
            -- Get auth account
            ro.val->'required_posting_auths'->>0 AS auth_account,
            -- Parse inner JSON
            hivemind_app.safe_parse_jsonb_tolerant(ro.val->>'json') AS inner_json
        FROM raw_ops ro
        WHERE jsonb_array_length(COALESCE(ro.val->'required_auths', '[]'::jsonb)) = 0
          AND jsonb_array_length(COALESCE(ro.val->'required_posting_auths', '[]'::jsonb)) = 1
    ),
    reblog_data AS (
        SELECT
            p.id,
            p.block_num,
            p.block_date,
            p.auth_account,
            -- Handle both array format ["reblog", {data}] and legacy format
            CASE
                WHEN jsonb_typeof(p.inner_json) = 'array'
                     AND jsonb_array_length(p.inner_json) = 2
                     AND p.inner_json->>0 = 'reblog'
                     AND jsonb_typeof(p.inner_json->1) = 'object'
                THEN p.inner_json->1
                WHEN jsonb_typeof(p.inner_json) = 'object'
                     AND p.block_num < 6000000
                THEN p.inner_json
                ELSE NULL
            END AS data
        FROM parsed p
        WHERE (p.val->>'id') IN ('follow', 'reblog')
    )
    SELECT
        rd.id,
        rd.block_num,
        rd.block_date,
        rd.auth_account,
        rd.data->>'account' AS account,
        rd.data->>'author' AS author,
        rd.data->>'permlink' AS permlink,
        COALESCE(rd.data->>'delete', '') = 'delete' AS is_delete
    FROM reblog_data rd
    WHERE rd.data IS NOT NULL
      AND rd.data ? 'account'
      AND rd.data ? 'author'
      AND rd.data ? 'permlink'
      -- account must match auth
      AND rd.data->>'account' = rd.auth_account;

    -- One block at a time an op resolves the post version live at the end of its block.
    -- An op of a block before the live version was created targets an earlier version,
    -- whose rows the posts phase has removed, or no post at all: it leaves the live
    -- version's row alone.
    DELETE FROM hivemind_app._reblog_ops r
    USING hivemind_app.hive_accounts ha, hivemind_app.hive_permlink_data hpd, hivemind_app.hive_posts hp
    WHERE ha.name = r.author
      AND hpd.permlink = r.permlink
      AND hp.author_id = ha.id AND hp.permlink_id = hpd.id
      AND hp.block_num_created <= _last_block AND (hp.counter_deleted = 0 OR hp.block_num > _last_block)
      AND r.block_num < hp.block_num_created;

    -- The op per (author, permlink, account) whose row the batch leaves, as the ops one
    -- block at a time leave it: the batch's last delete when no create follows it, else
    -- the first create after it (a later create finds that row and keeps it, its block
    -- and its notification). This handles create→delete→create within the same batch.
    INSERT INTO hivemind_app._reblog_final
    SELECT DISTINCT ON (o.author, o.permlink, o.account)
        o.id, o.account, o.author, o.permlink, o.block_date, o.block_num, o.is_delete
    FROM (
        SELECT r.*,
               COALESCE(max(r.id) FILTER (WHERE r.is_delete) OVER pair, 0) AS last_delete_id,
               max(r.id) OVER pair AS last_id
        FROM hivemind_app._reblog_ops r
        WINDOW pair AS (PARTITION BY r.author, r.permlink, r.account)
    ) o
    WHERE o.id > o.last_delete_id OR o.id = o.last_id
    ORDER BY o.author, o.permlink, o.account, o.id;

    -- Process deletes: delete entries where ANY delete exists in this batch
    -- (covers entries from previous batches that need cleanup)
    PERFORM hivemind_app.delete_reblog_feed_cache(
        ro.author::VARCHAR, ro.permlink::VARCHAR, ro.account::VARCHAR, _last_block
    )
    FROM (SELECT DISTINCT author, permlink, account FROM hivemind_app._reblog_ops WHERE is_delete) ro;

    -- Process creates: only insert where the FINAL action is a create
    WITH deduped AS (
        SELECT account, author, permlink, block_date, block_num
        FROM hivemind_app._reblog_final
        WHERE NOT is_delete
    ),
    validated AS (
        SELECT
            ha_b.id AS blogger_id,
            hp.id AS post_id,
            d.block_date AS created_at,
            d.block_num
        FROM deduped d
        JOIN hivemind_app.hive_accounts ha_b ON ha_b.name = d.account
        JOIN hivemind_app.hive_accounts ha ON ha.name = d.author
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = d.permlink
        JOIN hivemind_app.hive_posts hp
            ON hp.author_id = ha.id AND hp.permlink_id = hpd.id
            AND hp.block_num_created <= _last_block AND (hp.counter_deleted = 0 OR hp.block_num > _last_block)
        -- hive_reblogs ids (and the reblog notification counters that follow them) are
        -- drawn in _reblog_final's write order; its physical order need not keep it.
        ORDER BY d.author, d.permlink, d.account
    )
    INSERT INTO hivemind_app.hive_reblogs (blogger_id, post_id, created_at, block_num)
    SELECT blogger_id, post_id, created_at, block_num FROM validated
    ON CONFLICT ON CONSTRAINT hive_reblogs_ux1 DO NOTHING;

    GET DIAGNOSTICS _count = ROW_COUNT;

    -- Tables are cleared at start of next call, no drop needed
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 6. process_account_updates_from_staging()
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_account_updates_from_staging()
RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    -- Collect types 10 (ACCOUNT_UPDATE) and 43 (ACCOUNT_UPDATE_2) from staging
    -- Deduplicate per field: json_metadata from the last op of either type,
    -- posting_json_metadata from the last type 43 op (type 10 doesn't carry it).
    --
    -- Previous DISTINCT ON approach picked one row per account (highest op id).
    -- When the last op was type 10, it discarded the type 43's posting_json_metadata.

    -- In Hive protocol, an empty string for json_metadata or
    -- posting_json_metadata means "don't change this field"
    -- (see metadata_plugin.cpp — the update is skipped when size() == 0).
    -- Use FILTER + NULLIF to exclude empty values from aggregation so
    -- that COALESCE in the UPDATE preserves the existing stored value.

    -- Deterministic lock order (by id) prevents deadlocks with concurrent
    -- transactions that also update hive_accounts (e.g. process_follows_for_blocks).
    WITH deduped AS (
        SELECT
            s.val->>'account' AS account_name,
            -- json_metadata: last non-empty value from either op type
            (array_agg(s.val->>'json_metadata' ORDER BY s.id DESC)
                FILTER (WHERE NULLIF(s.val->>'json_metadata', '') IS NOT NULL))[1] AS json_metadata,
            -- posting_json_metadata: last non-empty value from type 43 only (type 10 doesn't carry it)
            (array_agg(s.val->>'posting_json_metadata' ORDER BY s.id DESC)
                FILTER (WHERE s.op_type_id = 43
                    AND NULLIF(s.val->>'posting_json_metadata', '') IS NOT NULL))[1] AS posting_json_metadata
        FROM hivemind_app._ops_staging_b s
        WHERE s.op_type_id IN (10, 43)
        GROUP BY s.val->>'account'
    ),
    locked AS (
        SELECT ha.id FROM hivemind_app.hive_accounts ha
        JOIN deduped d ON ha.name = d.account_name ORDER BY ha.id FOR UPDATE
    )
    UPDATE hivemind_app.hive_accounts ha
    SET
        posting_json_metadata = COALESCE(d.posting_json_metadata, ha.posting_json_metadata),
        json_metadata = COALESCE(d.json_metadata, ha.json_metadata)
    FROM deduped d
    WHERE ha.name = d.account_name;

    GET DIAGNOSTICS _count = ROW_COUNT;

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 7. process_lastread_from_staging()
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_lastread_from_staging()
RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    -- Extract 'notify' custom_json ops from staging (type 18, custom_json_id = 'notify')
    -- Parse setLastRead command, validate date, update hive_accounts

    WITH notify_ops AS (
        SELECT
            s.id,
            s.block_num,
            s.block_date,
            s.val->'required_posting_auths'->>0 AS account,
            hivemind_app.safe_parse_jsonb_tolerant(s.val->>'json') AS inner_json
        FROM hivemind_app._ops_staging_b s
        WHERE s.op_type_id = 18
          AND (s.val->>'id') = 'notify'
          AND jsonb_array_length(COALESCE(s.val->'required_auths', '[]'::jsonb)) = 0
          AND jsonb_array_length(COALESCE(s.val->'required_posting_auths', '[]'::jsonb)) = 1
    ),
    parsed AS (
        SELECT
            no.id,
            no.account,
            no.block_date,
            -- setLastRead command: inner_json is ['setLastRead', {date: ...}]
            CASE
                WHEN jsonb_typeof(no.inner_json) = 'array'
                     AND jsonb_array_length(no.inner_json) = 2
                     AND no.inner_json->>0 = 'setLastRead'
                     AND jsonb_typeof(no.inner_json->1) = 'object'
                THEN CASE
                    -- Validate date matches YYYY-MM-DDTHH:MM:SS before casting
                    WHEN (no.inner_json->1->>'date') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$'
                    THEN LEAST((no.inner_json->1->>'date')::TIMESTAMP, no.block_date)
                    ELSE no.block_date
                END
                ELSE NULL
            END AS read_date
        FROM notify_ops no
    ),
    -- Keep last setLastRead per account
    deduped AS (
        SELECT DISTINCT ON (account)
            account, read_date
        FROM parsed
        WHERE read_date IS NOT NULL
        ORDER BY account, id DESC
    ),
    -- Deterministic lock order (by id) prevents deadlocks with concurrent
    -- transactions that also update hive_accounts.
    locked AS (
        SELECT ha.id FROM hivemind_app.hive_accounts ha
        JOIN deduped d ON ha.name = d.account ORDER BY ha.id FOR UPDATE
    )
    UPDATE hivemind_app.hive_accounts ha
    SET lastread_at = d.read_date
    FROM deduped d
    WHERE ha.name = d.account;

    GET DIAGNOSTICS _count = ROW_COUNT;

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 8. process_payouts_from_staging(_last_safe_cashout_block)
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_payouts_from_staging(
    _last_safe_cashout_block INT DEFAULT 0
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    -- Payout virtual ops (types 51, 53, 61, 72) are applied as processing the batch
    -- one block at a time would apply them. block_payouts is one block's update of
    -- one post ("last" = the block's last op of that type); each block updates the
    -- version live at the end of that block, so a post deleted in a later block still
    -- takes its payout; version_payouts folds a version's blocks as successive
    -- updates would leave them.
    --
    -- Within a block, COMMENT_REWARD (type 53) supersedes EFFECTIVE_COMMENT_VOTE
    -- payout data, and COMMENT_PAYOUT_UPDATE (type 61) zeroes pending payout and
    -- total vote weight.
    WITH block_payouts AS (
        SELECT
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            s.block_num,
            -- COMMENT_PAYOUT_UPDATE (type 61)
            bool_or(s.op_type_id = 61) AS has_cpu,
            (array_agg(s.block_date ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 61))[1] AS cpu_payout_date,
            -- AUTHOR_REWARD (type 51) - last occurrence
            (array_agg((s.val->'hive_payout'->>'amount')::BIGINT ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 51))[1] AS author_rewards_hive,
            (array_agg((s.val->'hbd_payout'->>'amount')::BIGINT ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 51))[1] AS author_rewards_hbd,
            (array_agg((s.val->'vesting_payout'->>'amount')::BIGINT ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 51))[1] AS author_rewards_vests,
            -- COMMENT_REWARD (type 53) - last occurrence
            bool_or(s.op_type_id = 53) AS has_cr,
            (array_agg((s.val->>'author_rewards')::BIGINT ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 53))[1] AS author_rewards,
            (array_agg(s.val->'total_payout_value' ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 53))[1] AS total_payout_value,
            (array_agg(s.val->'curator_payout_value' ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 53))[1] AS curator_payout_value,
            (array_agg(s.val->'beneficiary_payout_value' ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 53))[1] AS beneficiary_payout_value,
            (array_agg(s.block_date ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 53))[1] AS cr_payout_date,
            -- EFFECTIVE_COMMENT_VOTE (type 72) - last occurrence, only if beyond safe cashout
            (array_agg(s.val->'pending_payout' ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 72 AND s.block_num > _last_safe_cashout_block))[1] AS pending_payout_json,
            (array_agg((s.val->>'total_vote_weight')::NUMERIC ORDER BY s.id DESC) FILTER (WHERE s.op_type_id = 72 AND s.block_num > _last_safe_cashout_block))[1] AS total_vote_weight
        FROM hivemind_app._ops_staging_b s
        WHERE s.op_type_id IN (51, 53, 61, 72)
        GROUP BY s.val->>'author', s.val->>'permlink', s.block_num
    ),
    pair_version AS MATERIALIZED (
        -- Every version of each paid post; a deleted version's block_num is the block
        -- that deleted it.
        SELECT
            t.author,
            t.permlink,
            hp.id AS post_id,
            hp.block_num_created,
            CASE WHEN hp.counter_deleted = 0 THEN NULL ELSE hp.block_num END AS deleted_block
        FROM (SELECT DISTINCT author, permlink FROM block_payouts) t
        JOIN hivemind_app.hive_accounts ha ON ha.name = t.author
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = t.permlink
        JOIN hivemind_app.hive_posts hp ON hp.author_id = ha.id AND hp.permlink_id = hpd.id
    ),
    version_payouts AS (
        -- A column one block leaves unchanged (NULL here) keeps the value of an earlier
        -- block, so each column is the last block's non-NULL value.
        SELECT
            pv.post_id,
            (array_agg(bp.cpu_payout_date ORDER BY bp.block_num DESC) FILTER (WHERE bp.has_cpu))[1] AS cpu_payout_date,
            bool_or(bp.has_cpu) AS has_cpu,
            (array_agg(bp.author_rewards_hive ORDER BY bp.block_num DESC) FILTER (WHERE bp.author_rewards_hive IS NOT NULL))[1] AS author_rewards_hive,
            (array_agg(bp.author_rewards_hbd ORDER BY bp.block_num DESC) FILTER (WHERE bp.author_rewards_hbd IS NOT NULL))[1] AS author_rewards_hbd,
            (array_agg(bp.author_rewards_vests ORDER BY bp.block_num DESC) FILTER (WHERE bp.author_rewards_vests IS NOT NULL))[1] AS author_rewards_vests,
            -- each block's COMMENT_REWARD adds its author_rewards
            sum(bp.author_rewards) AS author_rewards,
            (array_agg(bp.total_payout_value ORDER BY bp.block_num DESC) FILTER (WHERE bp.has_cr))[1] AS total_payout_value,
            (array_agg(bp.curator_payout_value ORDER BY bp.block_num DESC) FILTER (WHERE bp.has_cr))[1] AS curator_payout_value,
            (array_agg(bp.beneficiary_payout_value ORDER BY bp.block_num DESC) FILTER (WHERE bp.has_cr))[1] AS beneficiary_payout_value,
            (array_agg(COALESCE(bp.cr_payout_date, bp.cpu_payout_date) ORDER BY bp.block_num DESC)
                FILTER (WHERE bp.has_cr OR bp.has_cpu))[1] AS last_payout_at,
            (array_agg(
                CASE WHEN bp.has_cr OR bp.has_cpu THEN 0
                     ELSE hivemind_app.sbd_amount_from_json(bp.pending_payout_json)::DECIMAL(10,3) END
                ORDER BY bp.block_num DESC)
                FILTER (WHERE bp.has_cr OR bp.has_cpu OR bp.pending_payout_json IS NOT NULL))[1] AS pending_payout,
            (array_agg(CASE WHEN bp.has_cpu THEN 0 ELSE bp.total_vote_weight END ORDER BY bp.block_num DESC)
                FILTER (WHERE bp.has_cpu OR (NOT bp.has_cr AND bp.total_vote_weight IS NOT NULL)))[1] AS total_vote_weight,
            -- Max block_num across the version's payout ops (for replay detection)
            max(bp.block_num) AS max_payout_block
        FROM block_payouts bp
        JOIN pair_version pv
            ON pv.author = bp.author
            AND pv.permlink = bp.permlink
            AND pv.block_num_created <= bp.block_num
            AND (pv.deleted_block IS NULL OR pv.deleted_block > bp.block_num)
        GROUP BY pv.post_id
    )
    UPDATE hivemind_app.hive_posts hp
    SET
        total_payout_value = COALESCE(
            hivemind_app.legacy_amount(m.total_payout_value),
            hp.total_payout_value
        ),
        curator_payout_value = COALESCE(
            hivemind_app.legacy_amount(m.curator_payout_value),
            hp.curator_payout_value
        ),
        last_payout_block = GREATEST(hp.last_payout_block, COALESCE(m.max_payout_block, 0)),
        author_rewards = CASE
            WHEN m.author_rewards IS NOT NULL AND m.max_payout_block <= hp.last_payout_block
            THEN hp.author_rewards  -- replay: skip accumulation
            ELSE COALESCE(m.author_rewards, 0) + hp.author_rewards
        END,
        author_rewards_hive = COALESCE(m.author_rewards_hive, hp.author_rewards_hive),
        author_rewards_hbd = COALESCE(m.author_rewards_hbd, hp.author_rewards_hbd),
        author_rewards_vests = COALESCE(m.author_rewards_vests, hp.author_rewards_vests),
        payout = COALESCE(
            -- Compute payout from COMMENT_REWARD data
            CASE WHEN m.total_payout_value IS NOT NULL THEN
                (hivemind_app.sbd_amount(m.total_payout_value)
                 + hivemind_app.sbd_amount(m.curator_payout_value)
                 + hivemind_app.sbd_amount(m.beneficiary_payout_value))::DECIMAL(10,3)
            ELSE NULL END,
            hp.payout
        ),
        pending_payout = COALESCE(m.pending_payout, hp.pending_payout),
        payout_at = COALESCE(m.cpu_payout_date, hp.payout_at),
        last_payout_at = COALESCE(m.last_payout_at, hp.last_payout_at),
        cashout_time = CASE
            WHEN m.has_cpu THEN 'infinity'::TIMESTAMP
            ELSE hp.cashout_time
        END,
        is_paidout = CASE
            WHEN m.has_cpu THEN TRUE
            ELSE hp.is_paidout
        END,
        total_vote_weight = COALESCE(m.total_vote_weight, hp.total_vote_weight)
    FROM version_payouts m
    WHERE hp.id = m.post_id;

    GET DIAGNOSTICS _count = ROW_COUNT;

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- Helper: parse legacy amount string like "1.234 HBD" -> numeric
CREATE OR REPLACE FUNCTION hivemind_app.legacy_amount(_amount JSONB)
RETURNS TEXT AS $function$
DECLARE
    _raw BIGINT;
    _precision INT;
    _nai TEXT;
    _asset TEXT;
    _val DECIMAL;
BEGIN
    IF _amount IS NULL OR _amount = 'null'::jsonb THEN RETURN NULL; END IF;
    _raw := (_amount->>'amount')::BIGINT;
    _precision := COALESCE((_amount->>'precision')::INT, 3);
    _nai := _amount->>'nai';
    _asset := CASE _nai
        WHEN '@@000000021' THEN 'HIVE'
        WHEN '@@000000013' THEN 'HBD'
        WHEN '@@000000037' THEN 'VESTS'
        ELSE 'UNKNOWN'
    END;
    _val := _raw::NUMERIC / (10::NUMERIC ^ _precision);
    RETURN trim(to_char(_val, 'FM999999999990.' || repeat('0', _precision))) || ' ' || _asset;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END
$function$ LANGUAGE plpgsql IMMUTABLE;

-- Helper: extract numeric HBD value from NAI JSONB amount object
CREATE OR REPLACE FUNCTION hivemind_app.sbd_amount(_amount JSONB)
RETURNS DECIMAL AS $function$
DECLARE
    _raw BIGINT;
    _precision INT;
BEGIN
    IF _amount IS NULL OR _amount = 'null'::jsonb THEN RETURN 0; END IF;
    _raw := (_amount->>'amount')::BIGINT;
    _precision := COALESCE((_amount->>'precision')::INT, 3);
    RETURN _raw::NUMERIC / (10::NUMERIC ^ _precision);
EXCEPTION WHEN OTHERS THEN
    RETURN 0;
END
$function$ LANGUAGE plpgsql IMMUTABLE;

-- Helper: extract numeric value from JSON amount object (amount, precision, nai fields)
CREATE OR REPLACE FUNCTION hivemind_app.sbd_amount_from_json(_amount JSONB)
RETURNS DECIMAL AS $function$
DECLARE
    _raw BIGINT;
    _precision INT;
BEGIN
    IF _amount IS NULL THEN RETURN 0; END IF;
    _raw := (_amount->>'amount')::BIGINT;
    _precision := COALESCE((_amount->>'precision')::INT, 3);
    RETURN _raw::NUMERIC / (10::NUMERIC ^ _precision);
EXCEPTION WHEN OTHERS THEN
    RETURN 0;
END
$function$ LANGUAGE plpgsql IMMUTABLE;


-- Rows from which the posts and votes phases analyze a staging table they have just
-- refilled (process_posts_from_staging, process_root_posts_batch, process_comments_batch,
-- prepare_votes_from_staging).
CREATE OR REPLACE FUNCTION hivemind_app.staging_analyze_min_rows()
RETURNS INT AS $$
    SELECT 1000;
$$ LANGUAGE sql IMMUTABLE;


-- ============================================================================
-- 9. process_posts_from_staging()
-- ============================================================================

-- Reserves the next _count hive_posts ids, one per comment op of a batch, and returns
-- the id before the first: the op numbered seq_id (its rank among the batch's comment ops,
-- in operation order) owns _base + seq_id, whether it inserts a post or not. A post's id
-- is then its op's rank among all comment ops of the chain, whatever the batches were.
-- Every call keeps the sequence past the ids reserved, for an insert that draws the
-- column default.
CREATE OR REPLACE FUNCTION hivemind_app.reserve_post_ids(_count INT)
RETURNS INT AS $function$
DECLARE
    _base INT;
    _sequence_last INT;
BEGIN
    UPDATE hivemind_app._post_id_slots SET last_id = last_id + _count
    RETURNING last_id - _count INTO _base;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'hivemind_app._post_id_slots has no row: the runtime code (massive_sync.sql) was not loaded';
    END IF;

    SELECT CASE WHEN s.is_called THEN s.last_value ELSE s.last_value - 1 END
    INTO _sequence_last
    FROM hivemind_app.hive_posts_id_seq s;
    IF _base + _count > _sequence_last THEN
        PERFORM setval('hivemind_app.hive_posts_id_seq', _base + _count);
    END IF;
    RETURN _base;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- Return type for post processing results (needed by Python for PostDataCache)
DROP TYPE IF EXISTS hivemind_app.post_staging_result CASCADE;
CREATE TYPE hivemind_app.post_staging_result AS (
    seq_id        INT,       -- original index in staging
    post_id       INT,       -- hive_posts.id
    is_new_post   BOOLEAN,
    author_id     INT,
    permlink_id   INT,
    depth         SMALLINT,
    parent_id     INT,
    parent_author_id INT,
    community_id  INT,
    is_post_muted BOOLEAN,
    muted_reasons INT,
    block_num     INT,
    block_date    TIMESTAMP,
    op_body       JSONB      -- original op value (for PostDataCache body merging)
);

CREATE OR REPLACE FUNCTION hivemind_app.process_posts_from_staging(
    _community_support_start_block INT
) RETURNS SETOF hivemind_app.post_staging_result AS $function$
DECLARE
    _rec RECORD;
    _ineffective_keys TEXT[];
    _processed_count INT;
    _remaining INT;
    -- Step 7: delete handling
    _post_id INT;
    _delete_create_pairs TEXT[];
    _changed INT;
    _comment_rows INT;
    _analyze_staging BOOLEAN;
    _id_base INT;
BEGIN
    -- Persistent unlogged staging tables (avoids PL/pgSQL stale OID with temp tables)
    DELETE FROM hivemind_app._comment_staging;
    DELETE FROM hivemind_app._replay_pairs;
    DELETE FROM hivemind_app._post_results;
    DELETE FROM hivemind_app._deleted_posts;

    -- Step 1: Collect ineffective delete keys (type 73)
    SELECT array_agg((s.val->>'author') || '/' || (s.val->>'permlink'))
    INTO _ineffective_keys
    FROM hivemind_app._ops_staging s
    WHERE s.op_type_id = 73;
    _ineffective_keys := COALESCE(_ineffective_keys, '{}');

    -- Step 2: Collect all comment ops (type 1) with INT seq_id for hive_post_op_input
    -- (HAF operation IDs are BIGINT and overflow hive_post_op_input.seq_id INTEGER)
    -- is_first marks the first occurrence per (author, permlink) — only these go to batch functions.
    -- Subsequent occurrences are edits that need PostDataCache body merging but not re-insertion.
    INSERT INTO hivemind_app._comment_staging (seq_id, staging_id, is_first, block_num, block_date, author, permlink, parent_author, parent_permlink, op_body)
    SELECT
        ROW_NUMBER() OVER (ORDER BY s.id)::INT AS seq_id,
        s.id AS staging_id,
        (ROW_NUMBER() OVER (PARTITION BY s.val->>'author', s.val->>'permlink' ORDER BY s.id) = 1) AS is_first,
        s.block_num,
        s.block_date,
        s.val->>'author' AS author,
        s.val->>'permlink' AS permlink,
        s.val->>'parent_author' AS parent_author,
        s.val->>'parent_permlink' AS parent_permlink,
        s.val AS op_body
    FROM hivemind_app._ops_staging s
    WHERE s.op_type_id = 1;

    -- The staging tables are refilled every call, so the statistics autovacuum last took
    -- describe some earlier fill. Planned on a stale near-empty estimate, the joins on them
    -- below run as nested loops that scan the inner table once per outer row: quadratic
    -- in the comments of one call, which grow with the massive-sync batch size. Below
    -- staging_analyze_min_rows() rows any plan is cheap, and the ANALYZE (and the
    -- replanning it causes) would cost more than it saves.
    GET DIAGNOSTICS _comment_rows = ROW_COUNT;
    _analyze_staging := _comment_rows >= hivemind_app.staging_analyze_min_rows();
    -- A post takes the id of the comment op that creates it: ids follow operation order
    -- and do not depend on how the blocks were batched (reserve_post_ids).
    _id_base := hivemind_app.reserve_post_ids(_comment_rows);
    IF _analyze_staging THEN
        ANALYZE hivemind_app._comment_staging (seq_id, staging_id, is_first, is_replayed, author, permlink, parent_author, parent_permlink);
    END IF;

    -- Normalize parent_author/parent_permlink for edits (first occurrence determines parent)
    UPDATE hivemind_app._comment_staging cs
    SET parent_author = first_parent.parent_author,
        parent_permlink = first_parent.parent_permlink
    FROM (
        SELECT DISTINCT ON (author, permlink)
            author, permlink, parent_author, parent_permlink
        FROM hivemind_app._comment_staging
        ORDER BY author, permlink, seq_id
    ) first_parent
    WHERE cs.author = first_parent.author
      AND cs.permlink = first_parent.permlink
      AND (cs.parent_author IS DISTINCT FROM first_parent.parent_author
           OR cs.parent_permlink IS DISTINCT FROM first_parent.parent_permlink);

    -- Identify author/permlink pairs that have delete-create cycles
    _delete_create_pairs := COALESCE(ARRAY(
        SELECT DISTINCT (s_del.val->>'author') || '/' || (s_del.val->>'permlink')
        FROM hivemind_app._ops_staging s_del
        WHERE s_del.op_type_id = 17
          AND NOT ((s_del.val->>'author') || '/' || (s_del.val->>'permlink') = ANY(_ineffective_keys))
          AND EXISTS (
              SELECT 1 FROM hivemind_app._ops_staging s_cr
              WHERE s_cr.op_type_id = 1
                AND s_cr.val->>'author' = s_del.val->>'author'
                AND s_cr.val->>'permlink' = s_del.val->>'permlink'
                AND s_cr.id > s_del.id
          )
    ), '{}');

    -- Step 2b: Choose the ops Step 7b replays in chain order (_replay_pairs, is_replayed).
    -- Steps 4-5 run before any delete of the batch, so they resolve a comment's parent
    -- as it was before those deletes. The replay takes over: for a pair deleted and
    -- re-created in the batch, every op from its first delete on; for a comment op that
    -- comes after the replay took over its parent's pair, every op of its own pair from
    -- that one on (transitively); and every delete of those pairs and of the parents of
    -- replayed comments, so that no parent is deleted before a reply created under it.
    IF array_length(_delete_create_pairs, 1) > 0 THEN
        INSERT INTO hivemind_app._replay_pairs (author, permlink, replay_from)
        SELECT s.val->>'author', s.val->>'permlink', min(s.id)
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 17
          AND (s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_delete_create_pairs)
        GROUP BY 1, 2;

        LOOP
            INSERT INTO hivemind_app._replay_pairs AS rp (author, permlink, replay_from)
            SELECT cs.author, cs.permlink, min(cs.staging_id)
            FROM hivemind_app._comment_staging cs
            JOIN hivemind_app._replay_pairs parent
                ON parent.author = cs.op_body->>'parent_author'
               AND parent.permlink = cs.op_body->>'parent_permlink'
            WHERE cs.staging_id > parent.replay_from
            GROUP BY cs.author, cs.permlink
            ON CONFLICT (author, permlink) DO UPDATE SET replay_from = EXCLUDED.replay_from
            WHERE EXCLUDED.replay_from < rp.replay_from;

            GET DIAGNOSTICS _changed = ROW_COUNT;
            EXIT WHEN _changed = 0;
        END LOOP;

        UPDATE hivemind_app._comment_staging cs
        SET is_replayed = TRUE
        FROM hivemind_app._replay_pairs rp
        WHERE rp.author = cs.author AND rp.permlink = cs.permlink
          AND cs.staging_id >= rp.replay_from;

        INSERT INTO hivemind_app._replay_pairs (author, permlink)
        SELECT DISTINCT cs.op_body->>'parent_author', cs.op_body->>'parent_permlink'
        FROM hivemind_app._comment_staging cs
        WHERE cs.is_replayed AND cs.op_body->>'parent_author' != ''
        ON CONFLICT (author, permlink) DO NOTHING;
    END IF;

    -- Step 3: Bulk-insert permlinks and categories
    INSERT INTO hivemind_app.hive_permlink_data (permlink)
    SELECT DISTINCT p FROM (
        SELECT permlink AS p FROM hivemind_app._comment_staging
        UNION
        SELECT parent_permlink AS p FROM hivemind_app._comment_staging WHERE parent_author != ''
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO hivemind_app.hive_category_data (category)
    SELECT DISTINCT parent_permlink
    FROM hivemind_app._comment_staging
    WHERE parent_author IS NULL OR parent_author = ''
    ON CONFLICT (category) DO NOTHING;

    -- Step 4: Process root posts via batch function (first-occurrence only to avoid
    -- ON CONFLICT DO UPDATE affecting the same row twice)
    INSERT INTO hivemind_app._post_results
    SELECT br.seq_id, br.id, br.is_new_post, br.author_id, br.permlink_id,
           br.depth, br.parent_id, br.parent_author_id, br.community_id,
           br.is_post_muted, br.muted_reasons, cs.block_num, cs.block_date, cs.op_body
    FROM hivemind_app.process_root_posts_batch(
        ARRAY(
            SELECT ROW(cs.seq_id, cs.author, cs.permlink,
                       ''::VARCHAR, cs.parent_permlink,
                       cs.block_date, _community_support_start_block,
                       cs.block_num, ARRAY[]::VARCHAR[])::hivemind_app.hive_post_op_input
            FROM hivemind_app._comment_staging cs
            WHERE cs.is_first AND NOT cs.is_replayed
              AND (cs.parent_author IS NULL OR cs.parent_author = '')
            ORDER BY cs.seq_id
        ),
        _id_base
    ) br
    JOIN hivemind_app._comment_staging cs ON cs.seq_id = br.seq_id;

    -- Step 5: Process comments with wave-based resolution (first-occurrence only)
    -- Each wave resolves one level of parent-child dependency. Loop until all
    -- comments are resolved or no progress is made (truly missing parents).
    LOOP
        -- Each wave adds to _post_results, which the anti-joins below read (see _comment_staging's ANALYZE).
        IF _analyze_staging THEN
            ANALYZE hivemind_app._post_results (seq_id);
        END IF;

        -- Count unprocessed first-occurrence comments (not yet in results)
        SELECT count(*) INTO _remaining
        FROM hivemind_app._comment_staging cs
        WHERE cs.is_first AND NOT cs.is_replayed
          AND cs.parent_author IS NOT NULL AND cs.parent_author != ''
          AND NOT EXISTS (SELECT 1 FROM hivemind_app._post_results pr WHERE pr.seq_id = cs.seq_id);

        EXIT WHEN _remaining = 0;

        -- Process batch: pass unprocessed first-occurrence comments only
        INSERT INTO hivemind_app._post_results
        SELECT br.seq_id, br.id, br.is_new_post, br.author_id, br.permlink_id,
               br.depth, br.parent_id, br.parent_author_id, br.community_id,
               br.is_post_muted, br.muted_reasons, cs.block_num, cs.block_date, cs.op_body
        FROM hivemind_app.process_comments_batch(
            ARRAY(
                SELECT ROW(cs.seq_id, cs.author, cs.permlink,
                           cs.parent_author, cs.parent_permlink,
                           cs.block_date, _community_support_start_block,
                           cs.block_num, ARRAY[]::VARCHAR[])::hivemind_app.hive_post_op_input
                FROM hivemind_app._comment_staging cs
                WHERE cs.is_first AND NOT cs.is_replayed
                  AND cs.parent_author IS NOT NULL AND cs.parent_author != ''
                  AND NOT EXISTS (SELECT 1 FROM hivemind_app._post_results pr WHERE pr.seq_id = cs.seq_id)
                ORDER BY cs.seq_id
            ),
            _id_base
        ) br
        JOIN hivemind_app._comment_staging cs ON cs.seq_id = br.seq_id;

        GET DIAGNOSTICS _processed_count = ROW_COUNT;
        EXIT WHEN _processed_count = 0;
    END LOOP;

    -- Step 5b: Generate results for edit ops (is_first = false)
    -- These share post_id and metadata with the first occurrence but have their own op_body
    INSERT INTO hivemind_app._post_results
    SELECT cs.seq_id, pr_first.post_id, false, pr_first.author_id, pr_first.permlink_id,
           pr_first.depth, pr_first.parent_id, pr_first.parent_author_id,
           pr_first.community_id, pr_first.is_post_muted, pr_first.muted_reasons,
           cs.block_num, cs.block_date, cs.op_body
    FROM hivemind_app._comment_staging cs
    JOIN hivemind_app._comment_staging cs_first
        ON cs_first.author = cs.author AND cs_first.permlink = cs.permlink AND cs_first.is_first
    JOIN hivemind_app._post_results pr_first ON pr_first.seq_id = cs_first.seq_id
    WHERE NOT cs.is_first AND NOT cs.is_replayed;

    -- Step 5c: Update updated_at, active and block_num for edit ops
    -- Edits (is_first=false) don't go through the batch functions, so updated_at, active
    -- and block_num are stuck at the creation values. Update them to the last edit's values,
    -- as the batch functions' ON CONFLICT path does for the first op of each later block.
    -- block_num must be updated because notification timestamps use hp.block_num - 1
    -- (matching old Python behavior where edits updated block_num via ON CONFLICT).
    UPDATE hivemind_app.hive_posts hp
    SET updated_at = last_edit.block_date,
        active = last_edit.block_date,
        block_num = last_edit.block_num
    FROM (
        SELECT DISTINCT ON (pr.post_id)
            pr.post_id, cs.block_date, cs.block_num
        FROM hivemind_app._comment_staging cs
        JOIN hivemind_app._comment_staging cs_first
            ON cs_first.author = cs.author AND cs_first.permlink = cs.permlink AND cs_first.is_first
        JOIN hivemind_app._post_results pr ON pr.seq_id = cs_first.seq_id
        WHERE NOT cs.is_first AND NOT cs.is_replayed
        ORDER BY pr.post_id, cs.seq_id DESC
    ) last_edit
    WHERE hp.id = last_edit.post_id;

    -- Step 5d: Process tags for root posts
    -- Tags come from json_metadata.tags array + parent_permlink (category).
    -- Only root posts (parent_author is empty) get tags.
    -- json_metadata can be a JSON string (double-encoded) or an object; handle both.
    -- Malformed json_metadata is silently ignored (matching old Python try/except).
    -- Uses UNION ALL instead of nested ARRAY(SELECT...) inside LATERAL to avoid
    -- potential planner issues with deeply nested correlated subqueries.
    PERFORM hivemind_app.process_tags_batch(
        ARRAY(
            SELECT ROW(
                base.post_id,
                tags.tag_val::VARCHAR,
                base.is_new_post
            )::hivemind_app.post_tag_input
            FROM (
                SELECT pr.post_id, pr.is_new_post, cs.parent_permlink,
                       hivemind_app.safe_parse_jsonb_tolerant(cs.op_body->>'json_metadata') AS parsed_md
                FROM hivemind_app._comment_staging cs
                JOIN hivemind_app._post_results pr ON pr.seq_id = cs.seq_id
                WHERE cs.is_first
                  AND (cs.parent_author IS NULL OR cs.parent_author = '')
                -- OFFSET 0 keeps the planner from flattening base, which would run
                -- safe_parse_jsonb_tolerant (a subtransaction) in each of parsed_md's
                -- references below instead of once per post
                OFFSET 0
            ) base,
            LATERAL (
                SELECT jsonb_array_elements_text(base.parsed_md->'tags') AS tag_val
                WHERE base.parsed_md IS NOT NULL
                  AND base.parsed_md->'tags' IS NOT NULL
                  AND jsonb_typeof(base.parsed_md->'tags') = 'array'
                UNION ALL
                SELECT base.parent_permlink
            ) tags
        )
    );

    -- Step 5e: Process tags for EDITED root posts (last edit overrides creation tags).
    -- When a root post is created and then edited within the same batch, Step 5d only
    -- processes the first occurrence's tags. If the edit changes json_metadata.tags, those
    -- changes are lost. The old Python code processed each edit's tags via _split_into_passes,
    -- so subsequent passes overwrote the creation's tags via process_tags_batch(is_new_post=false).
    -- Here we process the LAST occurrence's tags for posts that have edits.
    PERFORM hivemind_app.process_tags_batch(
        ARRAY(
            SELECT ROW(
                base.post_id,
                tags.tag_val::VARCHAR,
                false  -- is_new_post = false so deleted_tags CTE removes stale tags
            )::hivemind_app.post_tag_input
            FROM (
                SELECT pr.post_id,
                       cs_first.parent_permlink,
                       hivemind_app.safe_parse_jsonb_tolerant(cs_last.op_body->>'json_metadata') AS parsed_md
                FROM hivemind_app._comment_staging cs_first
                JOIN hivemind_app._post_results pr ON pr.seq_id = cs_first.seq_id
                JOIN LATERAL (
                    SELECT cs2.op_body
                    FROM hivemind_app._comment_staging cs2
                    WHERE cs2.author = cs_first.author
                      AND cs2.permlink = cs_first.permlink
                      AND NOT cs2.is_first
                    ORDER BY cs2.seq_id DESC
                    LIMIT 1
                ) cs_last ON true
                WHERE cs_first.is_first
                  AND (cs_first.parent_author IS NULL OR cs_first.parent_author = '')
                OFFSET 0  -- parse once per post, as in Step 5d
            ) base,
            LATERAL (
                SELECT jsonb_array_elements_text(base.parsed_md->'tags') AS tag_val
                WHERE base.parsed_md IS NOT NULL
                  AND base.parsed_md->'tags' IS NOT NULL
                  AND jsonb_typeof(base.parsed_md->'tags') = 'array'
                UNION ALL
                SELECT base.parent_permlink
            ) tags
        )
    );

    -- Step 6: Process comment_options (type 19) - update hive_posts columns.
    -- DISTINCT ON keeps only the last op per (author, permlink) when the same
    -- post has multiple comment_options in one batch (e.g. post created with
    -- beneficiaries then edited clearing them). Without this, PostgreSQL's
    -- UPDATE FROM would non-deterministically pick any matching row.
    WITH co_ops AS (
        SELECT DISTINCT ON (s.val->>'author', s.val->>'permlink')
            s.id,
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            COALESCE(hivemind_app.legacy_amount(s.val->'max_accepted_payout'), '1000000.000 HBD') AS max_accepted_payout,
            COALESCE((s.val->>'percent_hbd')::INT, 10000) AS percent_hbd,
            COALESCE((s.val->>'allow_votes')::BOOLEAN, TRUE) AS allow_votes,
            COALESCE((s.val->>'allow_curation_rewards')::BOOLEAN, TRUE) AS allow_curation_rewards,
            COALESCE(
                (SELECT elem->'value'->'beneficiaries'
                 FROM jsonb_array_elements(s.val->'extensions') elem
                 WHERE elem->>'type' = 'comment_payout_beneficiaries'
                 LIMIT 1),
                '[]'::jsonb
            ) AS beneficiaries
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 19
        ORDER BY s.val->>'author', s.val->>'permlink', s.id DESC
    )
    UPDATE hivemind_app.hive_posts hp
    SET
        max_accepted_payout = co.max_accepted_payout,
        percent_hbd = co.percent_hbd,
        allow_votes = co.allow_votes,
        allow_curation_rewards = co.allow_curation_rewards,
        beneficiaries = co.beneficiaries
    FROM co_ops co
    JOIN hivemind_app.hive_accounts ha ON ha.name = co.author
    JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = co.permlink
    WHERE hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0;

    -- Step 7: Process deletes (type 17) and handle delete-create cycles.
    -- When a post is created, deleted, and re-created within the same batch,
    -- the old code processes these sequentially: each recreate gets a NEW row with
    -- a new post_id (so old votes don't carry over). We replicate this by:
    --   (a) simple deletes: no op of the pair is replayed → just delete as before
    --   (b) replayed ops (Step 2b): iterate them in chain order, alternating
    --       delete_hive_post and INSERT of new rows

    -- Every deleted version goes to _deleted_posts: Stage B removes its reblogs and feed
    -- cache rows (process_reblogs_from_staging) and takes it off its author's post_count
    -- (process_post_counts_from_staging), so that the next batch's posts phase, which
    -- pipelined massive sync runs beside that stage, writes neither hive_reblogs nor
    -- hive_accounts rows.
    --
    -- (a) Simple deletes: set-based bulk operation instead of per-row loop.
    -- Resolves all author/permlink pairs to post IDs in one join, then does
    -- bulk UPDATE + DELETE in a single data-modifying CTE.
    -- At full chain scale (783K delete ops), this replaces ~4.7M individual
    -- queries with set-based operations.
    WITH simple_delete_posts AS (
        SELECT
            hp.id AS post_id,
            hp.author_id,
            hp.permlink_id,
            s.block_num,
            s.block_date
        FROM hivemind_app._ops_staging s
        JOIN hivemind_app.hive_accounts ha ON ha.name = s.val->>'author'
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = s.val->>'permlink'
        JOIN hivemind_app.hive_posts hp
            ON hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0
        WHERE s.op_type_id = 17
          AND NOT ((s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_ineffective_keys))
          AND NOT EXISTS (
              SELECT 1 FROM hivemind_app._replay_pairs rp
              WHERE rp.author = s.val->>'author' AND rp.permlink = s.val->>'permlink'
          )
    ),
    updated_posts AS (
        UPDATE hivemind_app.hive_posts hp
        SET counter_deleted = (
                SELECT MAX(hps.counter_deleted) + 1
                FROM hivemind_app.hive_posts hps
                WHERE hps.author_id = hp.author_id AND hps.permlink_id = hp.permlink_id
            ),
            block_num = sd.block_num,
            active = sd.block_date
        FROM simple_delete_posts sd
        WHERE hp.id = sd.post_id
        RETURNING sd.post_id, sd.author_id
    ),
    del_tags AS (
        DELETE FROM hivemind_app.hive_post_tags
        WHERE post_id IN (SELECT post_id FROM updated_posts)
        RETURNING post_id
    )
    INSERT INTO hivemind_app._deleted_posts (post_id, author_id)
    SELECT post_id, author_id FROM updated_posts;

    -- (b) Replayed ops in chain order, across pairs: each comment op resolves its
    -- parent as it is at that op. A create of a pair with no live row inserts a new
    -- row with a fresh post_id; an edit updates the live one. Each op's result row
    -- carries the row it was applied to.
    IF array_length(_delete_create_pairs, 1) > 0 THEN
        FOR _rec IN
            SELECT cs.staging_id, cs.seq_id, 1 AS op_type_id, cs.author, cs.permlink,
                   cs.op_body->>'parent_author' AS parent_author,
                   cs.op_body->>'parent_permlink' AS parent_permlink,
                   cs.block_num, cs.block_date, cs.op_body
            FROM hivemind_app._comment_staging cs
            WHERE cs.is_replayed
            UNION ALL
            SELECT s.id, NULL, 17, s.val->>'author', s.val->>'permlink', NULL, NULL,
                   s.block_num, s.block_date, NULL
            FROM hivemind_app._ops_staging s
            JOIN hivemind_app._replay_pairs rp
                ON rp.author = s.val->>'author' AND rp.permlink = s.val->>'permlink'
            WHERE s.op_type_id = 17
              AND NOT ((s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_ineffective_keys))
            ORDER BY 1
        LOOP
            IF _rec.op_type_id = 17 THEN
                -- delete_hive_post deletes the pair's live row, when there is one
                _post_id := hivemind_app.find_comment_id(_rec.author::VARCHAR, _rec.permlink::VARCHAR, False);
                IF _post_id <> 0 THEN
                    INSERT INTO hivemind_app._deleted_posts (post_id, author_id)
                    SELECT hp.id, hp.author_id FROM hivemind_app.hive_posts hp WHERE hp.id = _post_id;
                END IF;
                PERFORM hivemind_app.delete_hive_post(
                    _rec.author::VARCHAR, _rec.permlink::VARCHAR, _rec.block_num, _rec.block_date
                );
            ELSE
                -- Structural fields come from this op's own parent_author/parent_permlink
                -- (a recreated post may differ, e.g. a root post recreated as a comment).
                INSERT INTO hivemind_app._post_results
                SELECT _rec.seq_id, op.id, op.is_new_post, op.author_id, op.permlink_id,
                       op.depth, op.parent_id, op.parent_author_id, op.community_id,
                       op.is_post_muted, op.muted_reasons, _rec.block_num, _rec.block_date, _rec.op_body
                FROM hivemind_app.process_hive_post_operation(
                    _rec.author, _rec.permlink,
                    COALESCE(_rec.parent_author, ''), COALESCE(_rec.parent_permlink, ''),
                    _rec.block_date, _community_support_start_block, _rec.block_num,
                    '{}'::VARCHAR[],  -- tags handled separately in Step 7d
                    _id_base + _rec.seq_id
                ) op;
            END IF;
        END LOOP;

        -- Step 7d: Re-process tags for recreated root posts.
        -- Tags for the old post_id were deleted by delete_hive_post; add them for the new post_id.
        PERFORM hivemind_app.process_tags_batch(
            ARRAY(
                WITH ld AS (
                    SELECT DISTINCT ON (s.val->>'author', s.val->>'permlink')
                        s.val->>'author' AS author, s.val->>'permlink' AS permlink,
                        s.id AS last_delete_staging_id
                    FROM hivemind_app._ops_staging s
                    WHERE s.op_type_id = 17
                      AND ((s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_delete_create_pairs))
                      AND NOT ((s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_ineffective_keys))
                    ORDER BY s.val->>'author', s.val->>'permlink', s.id DESC
                ),
                fa AS (
                    SELECT DISTINCT ON (ha.name, hpd.permlink)
                        ha.name AS author, hpd.permlink, hp.id AS new_post_id
                    FROM hivemind_app.hive_posts hp
                    JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
                    JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
                    WHERE hp.counter_deleted = 0
                      AND EXISTS (SELECT 1 FROM ld WHERE ld.author = ha.name AND ld.permlink = hpd.permlink)
                    ORDER BY ha.name, hpd.permlink, hp.id DESC
                )
                SELECT ROW(
                    fa.new_post_id,
                    tags.tag_val::VARCHAR,
                    TRUE
                )::hivemind_app.post_tag_input
                FROM fa
                JOIN hivemind_app.hive_posts hp ON hp.id = fa.new_post_id AND hp.depth = 0
                JOIN ld ON ld.author = fa.author AND ld.permlink = fa.permlink
                CROSS JOIN LATERAL (
                    SELECT jsonb_array_elements_text(parsed.md->'tags') AS tag_val
                    FROM (
                        SELECT hivemind_app.safe_parse_jsonb_tolerant(cs.op_body->>'json_metadata') AS md
                        FROM hivemind_app._comment_staging cs
                        WHERE cs.author = fa.author AND cs.permlink = fa.permlink
                          AND cs.staging_id > ld.last_delete_staging_id
                        ORDER BY cs.seq_id DESC LIMIT 1
                    ) parsed
                    WHERE parsed.md IS NOT NULL
                      AND parsed.md->'tags' IS NOT NULL
                      AND jsonb_typeof(parsed.md->'tags') = 'array'
                    UNION ALL
                    SELECT cs2.parent_permlink
                    FROM hivemind_app._comment_staging cs2
                    WHERE cs2.author = fa.author AND cs2.permlink = fa.permlink
                      AND cs2.is_first LIMIT 1
                ) tags
                WHERE tags.tag_val IS NOT NULL
            )
        );
    END IF;

    -- Step 7f: Re-apply comment_options for posts created by the replay.
    -- Step 6 ran before the replay, so comment_options (beneficiaries,
    -- max_accepted_payout, etc.) were applied to the original post which Step 7
    -- then deleted, or to no row. The replayed post has fresh defaults. Re-apply
    -- comment_options ops that came AFTER the last delete for each replayed pair.
    IF array_length(_delete_create_pairs, 1) > 0 THEN
        WITH last_delete AS (
            SELECT rp.author, rp.permlink, COALESCE(max(s.id), 0) AS last_delete_id
            FROM hivemind_app._replay_pairs rp
            LEFT JOIN hivemind_app._ops_staging s
                ON s.op_type_id = 17
               AND s.val->>'author' = rp.author AND s.val->>'permlink' = rp.permlink
               AND NOT ((s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_ineffective_keys))
            WHERE rp.replay_from IS NOT NULL
            GROUP BY rp.author, rp.permlink
        ),
        co_for_recreated AS (
            SELECT DISTINCT ON (s.val->>'author', s.val->>'permlink')
                s.val->>'author' AS author,
                s.val->>'permlink' AS permlink,
                COALESCE(hivemind_app.legacy_amount(s.val->'max_accepted_payout'), '1000000.000 HBD') AS max_accepted_payout,
                COALESCE((s.val->>'percent_hbd')::INT, 10000) AS percent_hbd,
                COALESCE((s.val->>'allow_votes')::BOOLEAN, TRUE) AS allow_votes,
                COALESCE((s.val->>'allow_curation_rewards')::BOOLEAN, TRUE) AS allow_curation_rewards,
                COALESCE(
                    (SELECT elem->'value'->'beneficiaries'
                     FROM jsonb_array_elements(s.val->'extensions') elem
                     WHERE elem->>'type' = 'comment_payout_beneficiaries'
                     LIMIT 1),
                    '[]'::jsonb
                ) AS beneficiaries
            FROM hivemind_app._ops_staging s
            JOIN last_delete ld
                ON ld.author = s.val->>'author' AND ld.permlink = s.val->>'permlink'
            WHERE s.op_type_id = 19
              AND s.id > ld.last_delete_id
            ORDER BY s.val->>'author', s.val->>'permlink', s.id DESC
        )
        UPDATE hivemind_app.hive_posts hp
        SET
            max_accepted_payout = co.max_accepted_payout,
            percent_hbd = co.percent_hbd,
            allow_votes = co.allow_votes,
            allow_curation_rewards = co.allow_curation_rewards,
            beneficiaries = co.beneficiaries
        FROM co_for_recreated co
        JOIN hivemind_app.hive_accounts ha ON ha.name = co.author
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = co.permlink
        WHERE hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0;
    END IF;

    -- Step 7e: Correct community type muting for posts created BEFORE updateProps.
    -- When updateProps runs in Phase 2.5 (before posts), ALL posts in blocks with
    -- a type-changing updateProps see the new type and get muted. But posts created
    -- BEFORE updateProps in the same block should NOT be muted by the new type —
    -- at their creation time the old type was still in effect (matching old Python
    -- behavior which processed ops in chronological order).
    -- Posts before updateProps can only have type muting (bit 1) and parent cascade
    -- (bit 2) — mutePost (bit 0) hasn't run yet — so clearing all muting is safe.
    WITH updateprops_type_changes AS (
        SELECT s.block_num, s.id AS staging_id,
               hivemind_app.safe_parse_jsonb_tolerant(s.val->>'json')->1->>'community' AS community_name
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 18
          AND s.val->>'id' = 'community'
          AND hivemind_app.safe_parse_jsonb_tolerant(s.val->>'json')->>0 = 'updateProps'
          AND hivemind_app.safe_parse_jsonb_tolerant(s.val->>'json')->1->'props'->>'type_id' IS NOT NULL
    ),
    posts_before_updateprops AS (
        SELECT pr.post_id
        FROM updateprops_type_changes utc
        JOIN hivemind_app.hive_communities hc ON hc.name = utc.community_name
        JOIN hivemind_app._comment_staging cs ON cs.block_num = utc.block_num
        JOIN hivemind_app._post_results pr ON pr.seq_id = cs.seq_id
        WHERE cs.staging_id < utc.staging_id
          AND pr.is_new_post
          AND pr.community_id = hc.id
          AND pr.muted_reasons != 0
    ),
    unmuted_posts AS (
        UPDATE hivemind_app.hive_posts hp
        SET is_muted = FALSE, muted_reasons = 0
        FROM posts_before_updateprops pbu
        WHERE hp.id = pbu.post_id
        RETURNING hp.id
    )
    UPDATE hivemind_app._post_results pr
    SET is_post_muted = FALSE, muted_reasons = 0
    FROM unmuted_posts u
    WHERE pr.post_id = u.id;

    -- (hive_accounts.post_count: process_post_counts_from_staging, in Stage B)

    -- Step 8: Generate muted post error notifications
    -- When a new post in a community is muted (muted_reasons != 0), generate an 'error'
    -- notification (type 10) for the post author, explaining why it was muted. Its counter
    -- is the op's rank among its block's comment ops, the seq_id a one-block batch gives it.
    INSERT INTO hivemind_app.hive_notification_cache
        (id, block_num, type_id, score, created_at, src, dst, post_id, dst_post_id,
         community, community_title, payload)
    SELECT
        hivemind_app.notification_id(pr.block_date, 10, (pr.seq_id - bf.first_seq_id + 1) % 4194303),
        pr.block_num,
        10,  -- error
        35,  -- default score
        pr.block_date,
        pr.community_id,  -- src = community
        pr.author_id,     -- dst = post author
        pr.post_id,
        pr.post_id,
        hc.name,
        hc.title,
        CASE
            WHEN pr.muted_reasons & 3 = 3 THEN
                CASE WHEN pr.depth > 0
                    THEN 'Post is muted because community type does not allow non members to post or comment and parent post/comment is muted'
                    ELSE 'Post is muted because community type does not allow non members to post and parent post/comment is muted'
                END
            WHEN pr.muted_reasons & 1 = 1 THEN
                CASE WHEN pr.depth > 0
                    THEN 'Post is muted because community type does not allow non members to post or comment'
                    ELSE 'Post is muted because community type does not allow non members to post'
                END
            WHEN pr.muted_reasons & 2 = 2 THEN
                'Post is muted because parent post/comment is muted'
            ELSE ''
        END
    FROM hivemind_app._post_results pr
    JOIN hivemind_app.hive_communities hc ON hc.id = pr.community_id
    JOIN (
        SELECT cs.block_num, min(cs.seq_id) AS first_seq_id
        FROM hivemind_app._comment_staging cs
        GROUP BY cs.block_num
    ) bf ON bf.block_num = pr.block_num
    WHERE pr.is_new_post
      AND pr.muted_reasons IS NOT NULL
      AND pr.muted_reasons != 0
      AND pr.community_id IS NOT NULL
      AND pr.block_num > (SELECT hivemind_app.block_before_irreversible('90 days'))
      AND pr.community_id IS DISTINCT FROM pr.author_id
    ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING;

    -- Return all post results
    RETURN QUERY SELECT * FROM hivemind_app._post_results ORDER BY seq_id;

    -- Tables are cleared at start of next call, no drop needed
END
$function$ LANGUAGE plpgsql VOLATILE;


-- Keeps the results of a massive batch's posts phase for a replay of the batch, in the
-- phase's transaction: replaying the comment ops on top of their own effects is not
-- idempotent (a post created and deleted in the batch would be created and deleted
-- again, and a created post would come back as an edit).
-- Saved for the batch starting at _first_block, with the post versions the phase deleted;
-- the rows of batches no longer in flight go.
DROP FUNCTION IF EXISTS hivemind_app.save_batch_post_results();
CREATE OR REPLACE FUNCTION hivemind_app.save_batch_post_results(_first_block INT)
RETURNS VOID AS $function$
BEGIN
    DELETE FROM hivemind_app._batch_post_results bpr
    WHERE bpr.first_block = _first_block
       OR NOT EXISTS (SELECT 1 FROM hivemind_app._batch_queue bq WHERE bq.first_block = bpr.first_block);
    INSERT INTO hivemind_app._batch_post_results
        (first_block, seq_id, post_id, is_new_post, author_id, permlink_id, depth,
         parent_id, parent_author_id, community_id, is_post_muted, muted_reasons)
    SELECT _first_block, pr.seq_id, pr.post_id, pr.is_new_post, pr.author_id, pr.permlink_id, pr.depth,
           pr.parent_id, pr.parent_author_id, pr.community_id, pr.is_post_muted, pr.muted_reasons
    FROM hivemind_app._post_results pr;

    DELETE FROM hivemind_app._batch_deleted_posts bdp
    WHERE bdp.first_block = _first_block
       OR NOT EXISTS (SELECT 1 FROM hivemind_app._batch_queue bq WHERE bq.first_block = bdp.first_block);
    INSERT INTO hivemind_app._batch_deleted_posts (first_block, post_id, author_id)
    SELECT _first_block, dp.post_id, dp.author_id FROM hivemind_app._deleted_posts dp;

    UPDATE hivemind_app._batch_queue SET posts_applied = TRUE WHERE first_block = _first_block;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- process_posts_from_staging's results for the batch starting at _first_block, whose posts
-- phase committed, from _batch_post_results and the reloaded _ops_staging (seq_id numbers
-- the comment ops as process_posts_from_staging does); refills _post_results and
-- _deleted_posts for the phases after it.
DROP FUNCTION IF EXISTS hivemind_app.restore_batch_post_results();
CREATE OR REPLACE FUNCTION hivemind_app.restore_batch_post_results(_first_block INT)
RETURNS SETOF hivemind_app.post_staging_result AS $function$
BEGIN
    DELETE FROM hivemind_app._post_results;
    INSERT INTO hivemind_app._post_results
    SELECT bpr.seq_id, bpr.post_id, bpr.is_new_post, bpr.author_id, bpr.permlink_id, bpr.depth,
           bpr.parent_id, bpr.parent_author_id, bpr.community_id, bpr.is_post_muted, bpr.muted_reasons,
           op.block_num, op.block_date, op.val
    FROM hivemind_app._batch_post_results bpr
    JOIN (
        SELECT ROW_NUMBER() OVER (ORDER BY s.id)::INT AS seq_id, s.block_num, s.block_date, s.val
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 1
    ) op ON op.seq_id = bpr.seq_id
    WHERE bpr.first_block = _first_block;

    DELETE FROM hivemind_app._deleted_posts;
    INSERT INTO hivemind_app._deleted_posts (post_id, author_id)
    SELECT bdp.post_id, bdp.author_id
    FROM hivemind_app._batch_deleted_posts bdp
    WHERE bdp.first_block = _first_block;

    RETURN QUERY SELECT * FROM hivemind_app._post_results ORDER BY seq_id;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- Step 7g of the posts phase, run in Stage B: keeps hive_accounts.post_count (live rows per
-- author) by the batch's net change, +1 per row inserted (every insert is live), -1 per
-- live row deleted. One UPDATE per author per batch, never one per post. Applied once per
-- in-flight batch (_batch_queue.post_counts_applied), as the counts are deltas.
CREATE OR REPLACE FUNCTION hivemind_app.process_post_counts_from_staging(_first_block INT)
RETURNS VOID AS $function$
BEGIN
    IF EXISTS (SELECT 1 FROM hivemind_app._batch_queue bq
               WHERE bq.first_block = _first_block AND bq.post_counts_applied) THEN
        RETURN;
    END IF;

    UPDATE hivemind_app.hive_accounts ha
    SET post_count = ha.post_count + d.delta
    FROM (
        SELECT c.author_id, SUM(c.delta)::INT AS delta
        FROM (
            SELECT pr.author_id, 1 AS delta FROM hivemind_app._post_results_b pr WHERE pr.is_new_post
            UNION ALL
            SELECT dp.author_id, -1 FROM hivemind_app._deleted_posts_b dp
        ) c
        GROUP BY c.author_id
        HAVING SUM(c.delta) <> 0
    ) d
    WHERE ha.id = d.author_id;

    UPDATE hivemind_app._batch_queue SET post_counts_applied = TRUE WHERE first_block = _first_block;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 9b. Validation helpers for community ops (match Python CommunityOp validation)
-- ============================================================================

-- Validate that a JSONB object contains exactly the expected keys (no extra, no missing).
-- Mirrors Python: assert_keys_match(self.op.keys(), schema, allow_missing=False)
DROP FUNCTION IF EXISTS hivemind_app._validate_json_keys(JSONB, TEXT[]);
CREATE OR REPLACE FUNCTION hivemind_app._validate_json_keys(
    _data JSONB,
    _required_keys TEXT[]
) RETURNS BOOLEAN AS $$
BEGIN
    -- All required keys must be present
    IF NOT (SELECT bool_and(_data ? k) FROM unnest(_required_keys) AS k) THEN
        RETURN FALSE;
    END IF;
    -- No extraneous keys
    IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(_data) AS k
        WHERE k != ALL(_required_keys)
    ) THEN
        RETURN FALSE;
    END IF;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Validate a string field in a JSONB object.
-- Mirrors Python: read_key_str(op, key, maxlen, allow_blank)
-- Checks: key exists, value is JSON string type, non-blank (unless allow_blank),
-- no whitespace padding (Python: assert op[key] == op[key].strip()), length limit.
DROP FUNCTION IF EXISTS hivemind_app._validate_str(JSONB, TEXT, INT, BOOLEAN);
CREATE OR REPLACE FUNCTION hivemind_app._validate_str(
    _data JSONB,
    _key TEXT,
    _maxlen INT DEFAULT NULL,
    _allow_blank BOOLEAN DEFAULT FALSE
) RETURNS BOOLEAN AS $$
DECLARE
    _val TEXT;
BEGIN
    -- Key must exist
    IF NOT _data ? _key THEN RETURN FALSE; END IF;
    -- Must be JSON string type (not number, null, bool, etc.)
    IF jsonb_typeof(_data->_key) != 'string' THEN RETURN FALSE; END IF;
    _val := _data->>_key;
    -- Non-blank check
    IF NOT _allow_blank AND (_val = '') THEN RETURN FALSE; END IF;
    -- Whitespace padding check
    IF _val != TRIM(both FROM _val) THEN RETURN FALSE; END IF;
    -- Length check
    IF _maxlen IS NOT NULL AND length(_val) > _maxlen THEN RETURN FALSE; END IF;
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Validate a language code against ISO 639-1.
-- Mirrors Python: LANGS tuple in community.py
DROP FUNCTION IF EXISTS hivemind_app._is_valid_lang(TEXT);
CREATE OR REPLACE FUNCTION hivemind_app._is_valid_lang(_lang TEXT) RETURNS BOOLEAN AS $$
SELECT _lang = ANY(ARRAY[
    'ab','aa','af','ak','sq','am','ar','an','hy','as','av','ae','ay','az',
    'bm','ba','eu','be','bn','bh','bi','bs','br','bg','my','ca','ch','ce',
    'ny','zh','cv','kw','co','cr','hr','cs','da','dv','nl','dz','en','eo',
    'et','ee','fo','fj','fi','fr','ff','gl','ka','de','el','gn','gu','ht',
    'ha','he','hz','hi','ho','hu','ia','id','ie','ga','ig','ik','io','is',
    'it','iu','ja','jv','kl','kn','kr','ks','kk','km','ki','rw','ky','kv',
    'kg','ko','ku','kj','la','lb','lg','li','ln','lo','lt','lu','lv','gv',
    'mk','mg','ms','ml','mt','mi','mr','mh','mn','na','nv','nd','ne','ng',
    'nb','nn','no','ii','nr','oc','oj','cu','om','or','os','pa','pi','fa',
    'pl','ps','pt','qu','rm','rn','ro','ru','sa','sc','sd','se','sm','sg',
    'sr','gd','sn','si','sk','sl','so','st','es','su','sw','ss','sv','ta',
    'te','tg','th','ti','bo','tk','tl','tn','to','tr','ts','tt','tw','ty',
    'ug','uk','ur','uz','ve','vi','vo','wa','cy','wo','fy','xh','yi','yo','za'
]);
$$ LANGUAGE sql IMMUTABLE;

-- ============================================================================
-- 9c. process_community_op — dispatch a single community custom_json action
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_community_op(
    _auth_account TEXT,
    _action TEXT,
    _data JSONB,
    _date TIMESTAMP,
    _block_num INT,
    _counter_in INT DEFAULT 0,
    _staging_op_id BIGINT DEFAULT NULL
) RETURNS INT AS $function$
DECLARE
    _actor_id INT;
    _community_name TEXT;
    _community_id INT;
    _account_name TEXT;
    _account_id INT;
    _permlink TEXT;
    _role TEXT;
    _role_id INT;
    _notes TEXT;
    _title TEXT;
    _props JSONB;
    _result RECORD;
    _notification_first_block INT;
    _counter INT;
    _score INT := 35;
    _type_id INT;
    _post_id INT;
    _props_title TEXT;
    _valid_props_keys TEXT[] := ARRAY['title', 'about', 'lang', 'is_nsfw', 'description', 'flag_text', 'settings', 'type_id'];
    _fallback_action_id SMALLINT := NULL;
    _fallback_old_value TEXT := NULL;
    _fallback_new_value TEXT := NULL;
    _fallback_notes TEXT := NULL;
    _fallback_prev_op_type INT;
    _fallback_is_muted BOOLEAN;
    _fallback_is_pinned BOOLEAN;
    _fallback_parent_id INT;
    _fallback_accepted BOOLEAN;
BEGIN
    -- ========= KEY VALIDATION (matches Python CommunityOp.SCHEMA + assert_keys_match) =========
    -- Python rejects ops with extraneous or missing keys; replicate that here.
    CASE _action
        WHEN 'subscribe' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community']) THEN RETURN _counter_in; END IF;
        WHEN 'unsubscribe' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community']) THEN RETURN _counter_in; END IF;
        WHEN 'updateProps' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'props']) THEN RETURN _counter_in; END IF;
        WHEN 'setRole' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'account', 'role']) THEN RETURN _counter_in; END IF;
        WHEN 'setUserTitle' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'account', 'title']) THEN RETURN _counter_in; END IF;
        WHEN 'mutePost' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'account', 'permlink', 'notes']) THEN RETURN _counter_in; END IF;
        WHEN 'unmutePost' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'account', 'permlink', 'notes']) THEN RETURN _counter_in; END IF;
        WHEN 'pinPost' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'account', 'permlink']) THEN RETURN _counter_in; END IF;
        WHEN 'unpinPost' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'account', 'permlink']) THEN RETURN _counter_in; END IF;
        WHEN 'flagPost' THEN
            IF NOT hivemind_app._validate_json_keys(_data, ARRAY['community', 'account', 'permlink', 'notes']) THEN RETURN _counter_in; END IF;
        ELSE
            RETURN _counter_in;  -- unknown action
    END CASE;

    -- ========= FIELD VALIDATION (matches Python read_key_str assertions) =========
    -- community: maxlen=16, non-blank, no whitespace padding
    IF NOT hivemind_app._validate_str(_data, 'community', 16) THEN RETURN _counter_in; END IF;

    -- Resolve actor
    SELECT id INTO _actor_id FROM hivemind_app.hive_accounts WHERE name = _auth_account;
    IF _actor_id IS NULL THEN RETURN _counter_in; END IF;

    -- Read community name (required for all actions)
    _community_name := _data->>'community';

    -- Validate community exists
    SELECT id INTO _community_id FROM hivemind_app.hive_communities WHERE name = _community_name;
    IF _community_id IS NULL THEN
        -- Generate error notification
        SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;
        IF _block_num > _notification_first_block THEN
            _counter_in := _counter_in + 1;
            INSERT INTO hivemind_app.hive_notification_cache
            (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
            VALUES (
                hivemind_app.notification_id(_date, 10, _counter_in),
                _block_num, 10, _date, _community_id, _actor_id, NULL, NULL, 35,
                'Community ''' || _community_name || ''' does not exist', '', ''
            ) ON CONFLICT DO NOTHING;
        END IF;
        RETURN _counter_in;
    END IF;

    -- Read action-specific fields
    IF _action IN ('setRole', 'setUserTitle', 'mutePost', 'unmutePost', 'pinPost', 'unpinPost', 'flagPost') THEN
        -- account: maxlen=16, non-blank, no padding
        IF NOT hivemind_app._validate_str(_data, 'account', 16) THEN RETURN _counter_in; END IF;
        _account_name := _data->>'account';
        SELECT id INTO _account_id FROM hivemind_app.hive_accounts WHERE name = _account_name;
        IF _account_id IS NULL THEN RETURN _counter_in; END IF;
    END IF;

    IF _action IN ('mutePost', 'unmutePost', 'pinPost', 'unpinPost', 'flagPost') THEN
        -- permlink: maxlen=256, non-blank, no padding
        IF NOT hivemind_app._validate_str(_data, 'permlink', 256) THEN RETURN _counter_in; END IF;
        _permlink := _data->>'permlink';
    END IF;

    IF _action IN ('mutePost', 'unmutePost', 'flagPost') THEN
        -- notes: maxlen=120, non-blank, no padding
        IF NOT hivemind_app._validate_str(_data, 'notes', 120) THEN RETURN _counter_in; END IF;
        _notes := _data->>'notes';
    END IF;

    -- Get notification threshold
    SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;

    -- Dispatch
    CASE _action
        WHEN 'updateProps' THEN
            _props := _data->'props';
            IF _props IS NULL OR jsonb_typeof(_props) != 'object' THEN RETURN _counter_in; END IF;
            -- Python: assert_keys_match(props.keys(), valid, allow_missing=True)
            -- No extraneous keys in props (missing allowed)
            IF EXISTS (
                SELECT 1 FROM jsonb_object_keys(_props) AS k
                WHERE k != ALL(_valid_props_keys)
            ) THEN RETURN _counter_in; END IF;
            -- Validate individual props fields (match Python _read_props)
            IF _props ? 'title' THEN
                -- read_key_str(props, 'title', 20): string, non-blank, no padding, maxlen=20
                IF NOT hivemind_app._validate_str(_props, 'title', 20) THEN RETURN _counter_in; END IF;
                _props_title := _props->>'title';
                -- assert len(out['title']) >= 3
                IF length(_props_title) < 3 THEN RETURN _counter_in; END IF;
                -- assert out['title'][0] not in ('@', '#')
                IF left(_props_title, 1) IN ('@', '#') THEN RETURN _counter_in; END IF;
            END IF;
            IF _props ? 'about' THEN
                -- read_key_str(props, 'about', 120, allow_blank=True)
                IF NOT hivemind_app._validate_str(_props, 'about', 120, TRUE) THEN RETURN _counter_in; END IF;
            END IF;
            IF _props ? 'lang' THEN
                -- read_key_str(props, 'lang', 2, 'lang')
                IF NOT hivemind_app._validate_str(_props, 'lang', 2) THEN RETURN _counter_in; END IF;
                IF NOT hivemind_app._is_valid_lang(_props->>'lang') THEN RETURN _counter_in; END IF;
            END IF;
            IF _props ? 'is_nsfw' THEN
                -- read_key_bool(props, 'is_nsfw'): must be JSON boolean
                IF jsonb_typeof(_props->'is_nsfw') != 'boolean' THEN RETURN _counter_in; END IF;
            END IF;
            IF _props ? 'description' THEN
                -- read_key_str(props, 'description', 1000, allow_blank=True)
                IF NOT hivemind_app._validate_str(_props, 'description', 1000, TRUE) THEN RETURN _counter_in; END IF;
            END IF;
            IF _props ? 'flag_text' THEN
                -- read_key_str(props, 'flag_text', 1000, allow_blank=True)
                IF NOT hivemind_app._validate_str(_props, 'flag_text', 1000, TRUE) THEN RETURN _counter_in; END IF;
            END IF;
            IF _props ? 'settings' THEN
                -- read_key_dict(props, 'settings'): must be non-empty object
                IF jsonb_typeof(_props->'settings') != 'object' THEN RETURN _counter_in; END IF;
                -- URL validation for avatar_url and cover_url
                IF _props->'settings' ? 'avatar_url' THEN
                    IF COALESCE(_props->'settings'->>'avatar_url', '') != '' THEN
                        IF left(_props->'settings'->>'avatar_url', 7) != 'http://'
                           AND left(_props->'settings'->>'avatar_url', 8) != 'https://' THEN
                            RETURN _counter_in;
                        END IF;
                        IF length(_props->'settings'->>'avatar_url') >= 1024 THEN RETURN _counter_in; END IF;
                    END IF;
                END IF;
                IF _props->'settings' ? 'cover_url' THEN
                    IF COALESCE(_props->'settings'->>'cover_url', '') != '' THEN
                        IF left(_props->'settings'->>'cover_url', 7) != 'http://'
                           AND left(_props->'settings'->>'cover_url', 8) != 'https://' THEN
                            RETURN _counter_in;
                        END IF;
                        IF length(_props->'settings'->>'cover_url') >= 1024 THEN RETURN _counter_in; END IF;
                    END IF;
                END IF;
            END IF;
            IF _props ? 'type_id' THEN
                -- read_key_integer(props, 'type_id'): must be int, in [1,2,3]
                IF jsonb_typeof(_props->'type_id') != 'number' THEN RETURN _counter_in; END IF;
                IF (_props->>'type_id')::INT NOT IN (1, 2, 3) THEN RETURN _counter_in; END IF;
            END IF;
            -- Python: assert out, 'props were blank' — at least one valid prop must exist
            -- (If all the above checks passed but no recognized field was present, props is empty)

            SELECT * INTO _result FROM hivemind_app.update_community_props(_actor_id, _community_id, _props);
            IF NOT _result.success THEN
                RAISE WARNING 'updateProps failed: community=% actor=% actor_id=% community_id=% error=%',
                    _community_name, _auth_account, _actor_id, _community_id, _result.error_message;
            END IF;
            -- Notify team on success
            IF _result.success AND _block_num > _notification_first_block THEN
                SELECT hivemind_app._community_notify_team(
                    _block_num, 3, _actor_id, _community_id, _date, NULL, _result.team_members, _props::TEXT, _counter_in
                ) INTO _counter_in;
            END IF;

        WHEN 'subscribe' THEN
            _counter_in := _counter_in + 1;
            SELECT * INTO _result FROM hivemind_app.community_subscribe(
                _actor_id, _community_id, _date, _block_num, _counter_in
            );

        WHEN 'unsubscribe' THEN
            SELECT * INTO _result FROM hivemind_app.community_unsubscribe(_actor_id, _community_id);

        WHEN 'setRole' THEN
            -- role: maxlen=16, non-blank, no padding (Python: read_key_str(self.op, 'role', 16))
            IF NOT hivemind_app._validate_str(_data, 'role', 16) THEN RETURN _counter_in; END IF;
            _role := _data->>'role';
            _role_id := CASE _role
                WHEN 'muted' THEN -2
                WHEN 'guest' THEN 0
                WHEN 'member' THEN 2
                WHEN 'mod' THEN 4
                WHEN 'admin' THEN 6
                WHEN 'owner' THEN 8
                ELSE NULL
            END;
            IF _role_id IS NULL THEN RETURN _counter_in; END IF;
            SELECT * INTO _result FROM hivemind_app.community_set_role(
                _actor_id, _account_id, _community_id, _role_id, _date, 100, 4
            );
            IF _result.success THEN
                INSERT INTO hivemind_app.hive_moderation_log
                    (community_id, action, actor_id, target_account_id, target_post_id,
                     old_value, new_value, notes, block_num, created_at)
                VALUES (
                    _community_id, 1, _actor_id, _account_id, NULL,
                    CASE COALESCE(_result.old_role_id, 0)
                        WHEN -2 THEN 'muted' WHEN 0 THEN 'guest' WHEN 2 THEN 'member'
                        WHEN 4 THEN 'mod' WHEN 6 THEN 'admin' WHEN 8 THEN 'owner'
                        ELSE 'guest'
                    END,
                    _role, NULL, _block_num, _date
                );
                IF _block_num > _notification_first_block THEN
                    _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                    _counter_in := _counter_in + 1;
                    INSERT INTO hivemind_app.hive_notification_cache
                    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                    VALUES (
                        hivemind_app.notification_id(_date, 2, _counter_in),
                        _block_num, 2, _date, _actor_id, _account_id, NULL, NULL, _score, _role, _community_name, ''
                    ) ON CONFLICT DO NOTHING;
                END IF;
            END IF;

        WHEN 'setUserTitle' THEN
            -- title: maxlen=32, allow_blank, no padding (Python: read_key_str(self.op, 'title', 32, allow_blank=True))
            IF NOT hivemind_app._validate_str(_data, 'title', 32, TRUE) THEN RETURN _counter_in; END IF;
            _title := COALESCE(TRIM(_data->>'title'), '');
            SELECT * INTO _result FROM hivemind_app.community_set_title(
                _actor_id, _account_id, _community_id, _title, _date
            );
            IF _result.success THEN
                INSERT INTO hivemind_app.hive_moderation_log
                    (community_id, action, actor_id, target_account_id, target_post_id,
                     old_value, new_value, notes, block_num, created_at)
                VALUES (
                    _community_id, 2, _actor_id, _account_id, NULL,
                    COALESCE(_result.old_title, ''), _title, NULL, _block_num, _date
                );
                IF _block_num > _notification_first_block THEN
                    _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                    _counter_in := _counter_in + 1;
                    INSERT INTO hivemind_app.hive_notification_cache
                    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                    VALUES (
                        hivemind_app.notification_id(_date, 4, _counter_in),
                        _block_num, 4, _date, _actor_id, _account_id, NULL, NULL, _score, _title, _community_name, ''
                    ) ON CONFLICT DO NOTHING;
                END IF;
            END IF;

        WHEN 'mutePost' THEN
            SELECT * INTO _result FROM hivemind_app.community_mute_post(
                _actor_id, _community_id, _account_id, _permlink, 1  -- muted_reasons bitmask: bit 0 = community moderation
            );
            IF _result.success THEN
                INSERT INTO hivemind_app.hive_moderation_log
                    (community_id, action, actor_id, target_account_id, target_post_id,
                     old_value, new_value, notes, block_num, created_at)
                VALUES (
                    _community_id, 3, _actor_id, _account_id, _result.post_id,
                    'unmuted', 'muted', _notes, _block_num, _date
                );
                IF _block_num > _notification_first_block THEN
                    _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                    _counter_in := _counter_in + 1;
                    INSERT INTO hivemind_app.hive_notification_cache
                    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                    VALUES (
                        hivemind_app.notification_id(_date, 5, _counter_in),
                        _block_num, 5, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                    ) ON CONFLICT DO NOTHING;
                END IF;
            ELSIF _result.error_message LIKE 'post does not exists%' THEN
                _fallback_action_id := 3;
                _fallback_old_value := 'unmuted';
                _fallback_new_value := 'muted';
                _fallback_notes := _notes;
            END IF;

        WHEN 'unmutePost' THEN
            SELECT * INTO _result FROM hivemind_app.community_unmute_post(
                _actor_id, _community_id, _account_id, _permlink
            );
            IF _result.success THEN
                INSERT INTO hivemind_app.hive_moderation_log
                    (community_id, action, actor_id, target_account_id, target_post_id,
                     old_value, new_value, notes, block_num, created_at)
                VALUES (
                    _community_id, 4, _actor_id, _account_id, _result.post_id,
                    'muted', 'unmuted', _notes, _block_num, _date
                );
                IF _block_num > _notification_first_block THEN
                    _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                    _counter_in := _counter_in + 1;
                    INSERT INTO hivemind_app.hive_notification_cache
                    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                    VALUES (
                        hivemind_app.notification_id(_date, 6, _counter_in),
                        _block_num, 6, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                    ) ON CONFLICT DO NOTHING;
                END IF;
            ELSIF _result.error_message LIKE 'post does not exists%' THEN
                _fallback_action_id := 4;
                _fallback_old_value := 'muted';
                _fallback_new_value := 'unmuted';
                _fallback_notes := _notes;
            END IF;

        WHEN 'pinPost' THEN
            SELECT * INTO _result FROM hivemind_app.community_pin_post(
                _actor_id, _community_id, _account_id, _permlink
            );
            IF _result.success THEN
                INSERT INTO hivemind_app.hive_moderation_log
                    (community_id, action, actor_id, target_account_id, target_post_id,
                     old_value, new_value, notes, block_num, created_at)
                VALUES (
                    _community_id, 5, _actor_id, _account_id, _result.post_id,
                    'unpinned', 'pinned', NULL, _block_num, _date
                );
                IF _block_num > _notification_first_block THEN
                    _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                    _counter_in := _counter_in + 1;
                    INSERT INTO hivemind_app.hive_notification_cache
                    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                    VALUES (
                        hivemind_app.notification_id(_date, 7, _counter_in),
                        _block_num, 7, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                    ) ON CONFLICT DO NOTHING;
                END IF;
            ELSIF _result.error_message LIKE 'post does not exists%' THEN
                _fallback_action_id := 5;
                _fallback_old_value := 'unpinned';
                _fallback_new_value := 'pinned';
                _fallback_notes := NULL;
            END IF;

        WHEN 'unpinPost' THEN
            SELECT * INTO _result FROM hivemind_app.community_unpin_post(
                _actor_id, _community_id, _account_id, _permlink
            );
            IF _result.success THEN
                INSERT INTO hivemind_app.hive_moderation_log
                    (community_id, action, actor_id, target_account_id, target_post_id,
                     old_value, new_value, notes, block_num, created_at)
                VALUES (
                    _community_id, 6, _actor_id, _account_id, _result.post_id,
                    'pinned', 'unpinned', NULL, _block_num, _date
                );
                IF _block_num > _notification_first_block THEN
                    _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                    _counter_in := _counter_in + 1;
                    INSERT INTO hivemind_app.hive_notification_cache
                    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                    VALUES (
                        hivemind_app.notification_id(_date, 8, _counter_in),
                        _block_num, 8, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                    ) ON CONFLICT DO NOTHING;
                END IF;
            ELSIF _result.error_message LIKE 'post does not exists%' THEN
                _fallback_action_id := 6;
                _fallback_old_value := 'pinned';
                _fallback_new_value := 'unpinned';
                _fallback_notes := NULL;
            END IF;

        WHEN 'flagPost' THEN
            SELECT * INTO _result FROM hivemind_app.community_flag_post(
                _actor_id, _community_id, _account_id, _permlink, _community_name
            );
            IF _result.success THEN
                INSERT INTO hivemind_app.hive_moderation_log
                    (community_id, action, actor_id, target_account_id, target_post_id,
                     old_value, new_value, notes, block_num, created_at)
                VALUES (
                    _community_id, 7, _actor_id, _account_id, _result.post_id,
                    NULL, 'flagged', _notes, _block_num, _date
                );
                IF _block_num > _notification_first_block THEN
                    SELECT hivemind_app._community_notify_team(
                        _block_num, 9, _actor_id, _community_id, _date, _result.post_id, _result.team_members, _notes, _counter_in
                    ) INTO _counter_in;
                END IF;
            ELSIF _result.error_message LIKE 'post does not exists%' THEN
                _fallback_action_id := 7;
                _fallback_old_value := NULL;
                _fallback_new_value := 'flagged';
                _fallback_notes := _notes;
            END IF;

        ELSE
            RETURN _counter_in;  -- Unknown action
    END CASE;

    -- Post-targeting op on a post deleted later in the same batch. The post row is already
    -- marked deleted by the time this runs, so the community_* function could not find it.
    -- Find the row that was live when the op was issued and repeat the checks the function
    -- makes, so the log holds what a block-by-block sync records.
    IF _fallback_action_id IS NOT NULL AND _staging_op_id IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM hivemind_app._ops_staging d
            WHERE d.op_type_id = 17  -- delete_comment
              AND d.val->>'author' = _account_name
              AND d.val->>'permlink' = _permlink
              AND d.id > _staging_op_id
        ) THEN
            -- Last comment (1) / delete_comment (17) of this post before the op, when the batch has one.
            SELECT s.op_type_id INTO _fallback_prev_op_type
            FROM hivemind_app._ops_staging s
            WHERE s.op_type_id IN (1, 17)
              AND s.val->>'author' = _account_name
              AND s.val->>'permlink' = _permlink
              AND s.id < _staging_op_id
            ORDER BY s.id DESC LIMIT 1;

            -- A deleted row keeps its creation date and takes the block of its deletion, so the row
            -- live at the op was created no later than the op and deleted no earlier. A delete just
            -- before the op means nothing was live; with no earlier op in the batch, a row created
            -- in the op's own block was created after it.
            _post_id := NULL;
            IF _fallback_prev_op_type IS DISTINCT FROM 17 THEN
                SELECT hp.id, hp.is_muted, hp.is_pinned, hp.parent_id
                INTO _post_id, _fallback_is_muted, _fallback_is_pinned, _fallback_parent_id
                FROM hivemind_app.hive_posts hp
                JOIN hivemind_app.hive_permlink_data hpd ON hp.permlink_id = hpd.id
                WHERE hp.author_id = _account_id
                  AND hpd.permlink = _permlink
                  AND hp.community_id = _community_id
                  AND hp.counter_deleted <> 0
                  AND hp.block_num >= _block_num
                  AND (hp.created_at < _date OR (_fallback_prev_op_type = 1 AND hp.created_at = _date))
                ORDER BY hp.id DESC LIMIT 1;
            END IF;

            IF _post_id IS NOT NULL THEN
                -- Same conditions and flag updates as community_{mute,unmute,pin,unpin,flag}_post,
                -- so a repeated action in the batch is rejected like it is on a live post.
                _fallback_accepted := FALSE;
                CASE _fallback_action_id
                    WHEN 3 THEN
                        IF NOT _fallback_is_muted THEN
                            UPDATE hivemind_app.hive_posts SET is_muted = true, muted_reasons = 1 WHERE id = _post_id;
                            _fallback_accepted := TRUE;
                        END IF;
                    WHEN 4 THEN
                        IF _fallback_is_muted AND NOT COALESCE(
                            (SELECT php.is_muted FROM hivemind_app.hive_posts php WHERE php.id = _fallback_parent_id), FALSE
                        ) THEN
                            UPDATE hivemind_app.hive_posts SET is_muted = false, muted_reasons = 0 WHERE id = _post_id;
                            _fallback_accepted := TRUE;
                        END IF;
                    WHEN 5 THEN
                        IF NOT _fallback_is_pinned THEN
                            UPDATE hivemind_app.hive_posts SET is_pinned = true WHERE id = _post_id;
                            _fallback_accepted := TRUE;
                        END IF;
                    WHEN 6 THEN
                        IF _fallback_is_pinned THEN
                            UPDATE hivemind_app.hive_posts SET is_pinned = false WHERE id = _post_id;
                            _fallback_accepted := TRUE;
                        END IF;
                    WHEN 7 THEN
                        -- community_flag_post finds an earlier flag by its notification, which exists
                        -- only past _notification_first_block; this path writes none, so use the log.
                        _fallback_accepted := NOT EXISTS (
                            SELECT 1 FROM hivemind_app.hive_moderation_log ml
                            WHERE ml.target_post_id = _post_id
                              AND ml.action = 7
                              AND ml.actor_id = _actor_id
                              AND ml.community_id = _community_id
                              AND ml.block_num > _notification_first_block
                        );
                    ELSE
                        NULL;
                END CASE;

                IF _fallback_accepted THEN
                    INSERT INTO hivemind_app.hive_moderation_log
                        (community_id, action, actor_id, target_account_id, target_post_id,
                         old_value, new_value, notes, block_num, created_at)
                    VALUES (
                        _community_id, _fallback_action_id, _actor_id, _account_id, _post_id,
                        _fallback_old_value, _fallback_new_value, _fallback_notes, _block_num, _date
                    );
                END IF;
            END IF;
        END IF;
    END IF;

    -- Generate error notification on failure
    IF _result IS NOT NULL AND NOT _result.success AND _result.error_message IS NOT NULL AND _result.error_message != '' THEN
        IF _block_num > _notification_first_block THEN
            _counter_in := _counter_in + 1;
            INSERT INTO hivemind_app.hive_notification_cache
            (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
            VALUES (
                hivemind_app.notification_id(_date, 10, _counter_in),
                _block_num, 10, _date, _community_id, _actor_id, NULL, NULL, 35,
                _result.error_message, _community_name, ''
            ) ON CONFLICT DO NOTHING;
        END IF;
    END IF;
    RETURN _counter_in;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- Helper: notify team members (mods/admins/owners) about a community action
CREATE OR REPLACE FUNCTION hivemind_app._community_notify_team(
    _block_num INT,
    _type_id INT,
    _actor_id INT,
    _community_id INT,
    _date TIMESTAMP,
    _post_id INT,
    _team_members INT[],
    _payload TEXT,
    _starting_counter INT
) RETURNS INT AS $function$
DECLARE
    _member_id INT;
    _counter INT := _starting_counter;
    _community_name TEXT;
BEGIN
    SELECT name INTO _community_name FROM hivemind_app.hive_communities WHERE id = _community_id;
    FOREACH _member_id IN ARRAY COALESCE(_team_members, ARRAY[]::INT[])
    LOOP
        IF _member_id = _actor_id THEN CONTINUE; END IF;
        _counter := _counter + 1;
        INSERT INTO hivemind_app.hive_notification_cache
        (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
        VALUES (
            hivemind_app.notification_id(_date, _type_id, _counter),
            _block_num, _type_id, _date, _actor_id, _member_id, _post_id, _post_id, 35,
            COALESCE(_payload, ''), COALESCE(_community_name, ''), ''
        ) ON CONFLICT DO NOTHING;
    END LOOP;
    RETURN _counter;
END
$function$ LANGUAGE plpgsql VOLATILE;

-- ============================================================================
-- 10. process_community_from_staging()
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_community_from_staging(
    _community_support_start_block INT,
    _phase INT DEFAULT 0,
    _cutoff_op_id BIGINT DEFAULT 0
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
    _rec RECORD;
    _val JSONB;
    _inner_json JSONB;
    _auth_account TEXT;
    _data JSONB;
    _action TEXT;
    _is_state_action BOOLEAN;
    _community_counter INT := 0;
    _last_counter_block INT := 0;
BEGIN
    -- Process community custom_json ops from staging (type 18, custom_json_id = 'community')
    -- Each action type dispatches to an existing SQL function
    --
    -- _phase controls which actions to process:
    --   0 = all actions (default, used by live sync)
    --   1 = ALL state ops (subscribe, unsubscribe, setRole, updateProps, setUserTitle)
    --       Must be committed before posts so role/metadata lookups are correct
    --   2 = post-targeting ops only (mutePost, unmutePost, pinPost, unpinPost, flagPost)

    FOR _rec IN
        SELECT
            s.id,
            s.block_num,
            s.block_date,
            s.val
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 18
          AND (s.val->>'id') = 'community'
          AND s.block_num > _community_support_start_block
        ORDER BY s.id
    LOOP
        _val := _rec.val;

        -- Auth validation
        IF jsonb_array_length(COALESCE(_val->'required_auths', '[]'::jsonb)) != 0 THEN
            CONTINUE;
        END IF;
        IF jsonb_array_length(COALESCE(_val->'required_posting_auths', '[]'::jsonb)) != 1 THEN
            CONTINUE;
        END IF;
        _auth_account := _val->'required_posting_auths'->>0;

        -- Parse inner JSON (use tolerant version to skip malformed rows gracefully
        -- rather than aborting the entire community processing loop)
        _inner_json := hivemind_app.safe_parse_jsonb_tolerant(_val->>'json');
        IF _inner_json IS NULL THEN CONTINUE; END IF;

        -- Must be array of length 2: ['action', {data}]
        IF jsonb_typeof(_inner_json) != 'array' OR jsonb_array_length(_inner_json) != 2 THEN
            CONTINUE;
        END IF;

        _action := _inner_json->>0;
        _data := _inner_json->1;

        IF jsonb_typeof(_data) != 'object' THEN
            CONTINUE;
        END IF;

        -- State actions must run before posts (Phase 2.5) so role/metadata lookups
        -- are correct during post creation. mutePost/unmutePost are NOT state actions —
        -- they target existing posts and must run AFTER posts are created (Phase 3a).
        _is_state_action := _action IN (
            'subscribe', 'unsubscribe', 'setRole', 'updateProps', 'setUserTitle'
        );

        -- Phase filtering:
        --   0 = all actions (default, used by live sync)
        --   1 = state actions only (before posts: subscribe, setRole, updateProps, setUserTitle)
        --   2 = post-targeting ops only (after posts: mutePost, unmutePost, pinPost, etc.)
        IF _phase = 1 THEN
            IF NOT _is_state_action THEN CONTINUE; END IF;
        END IF;
        IF _phase = 2 THEN
            IF _is_state_action THEN CONTINUE; END IF;
        END IF;

        -- For mutePost/unmutePost in Phase 2: skip if a delete_comment for the same
        -- (author, permlink) exists AFTER this op in the batch. The mute was targeting
        -- a post that gets deleted; the recreated post shouldn't inherit the mute.
        -- Without this, Phase 3a applies mutePost to the recreated post (only active row).
        IF _phase = 2 AND _action IN ('mutePost', 'unmutePost') THEN
            IF EXISTS (
                SELECT 1 FROM hivemind_app._ops_staging d
                WHERE d.op_type_id = 17  -- delete_comment
                  AND d.val->>'author' = _data->>'account'
                  AND d.val->>'permlink' = _data->>'permlink'
                  AND d.id > _rec.id
            ) THEN
                CONTINUE;
            END IF;
        END IF;

        -- Per-block counter for community notifications (resets when block changes)
        IF _rec.block_num != _last_counter_block THEN
            _community_counter := 0;
            _last_counter_block := _rec.block_num;
        END IF;

        -- Dispatch to existing community SQL functions.
        -- No EXCEPTION WHEN OTHERS wrapper: with proper validation in process_community_op,
        -- the underlying SQL functions should not throw. If they do, it's a bug that should
        -- propagate rather than be silently swallowed. The old wrapper also created an
        -- implicit savepoint per iteration (PL/pgSQL subtransaction), adding overhead.
        SELECT hivemind_app.process_community_op(
            _auth_account, _action, _data, _rec.block_date, _rec.block_num, _community_counter, _rec.id
        ) INTO _community_counter;
        _count := _count + 1;
    END LOOP;

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 10b. propagate_muted_parent_for_batch
-- After mutePost/unmutePost are applied (Phase 3a), child posts created in
-- the same batch don't yet know their parent was muted (because mutePost runs
-- AFTER all posts are created in Phase 3). This function recursively propagates
-- MUTED_PARENT (muted_reasons bit 2 = value 4) to descendants of newly-muted posts.
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.propagate_muted_parent_for_batch(
    _first_block INT, _last_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT;
BEGIN
    -- Early exit: skip expensive recursive scan if no mutePost ops exist in the
    -- current batch. The staging table is small (~1000 blocks of ops) so this
    -- check is instant, while the recursive CTE below requires a full sequential
    -- scan of hive_posts during MASSIVE_WITHOUT_INDEXES mode (~15s per call).
    IF NOT EXISTS (
        SELECT 1 FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 18
          AND (s.val->>'id') = 'community'
          AND s.val->>'json' LIKE '%mutePost%'
    ) THEN
        RETURN 0;
    END IF;

    -- Recursively find all descendants of posts that were muted by community
    -- moderation (mutePost) in the current batch and propagate MUTED_PARENT.
    WITH RECURSIVE muted_descendants AS (
        -- Seed: posts muted by community moderation (bit 0) in this batch
        SELECT hp.id
        FROM hivemind_app.hive_posts hp
        WHERE hp.is_muted = true
          AND hp.muted_reasons & 1 = 1  -- MUTED_COMMUNITY_MODERATION
          AND hp.block_num BETWEEN _first_block AND _last_block

        UNION ALL

        -- Recurse: direct children of any muted post
        SELECT child.id
        FROM hivemind_app.hive_posts child
        JOIN muted_descendants parent ON child.parent_id = parent.id
        WHERE child.counter_deleted = 0
    )
    UPDATE hivemind_app.hive_posts hp
    SET is_muted = true,
        muted_reasons = hp.muted_reasons | 4  -- add MUTED_PARENT bit
    FROM muted_descendants md
    WHERE hp.id = md.id
      AND hp.muted_reasons & 1 = 0  -- Don't modify the root muted posts themselves
      AND (hp.is_muted = false OR hp.muted_reasons & 4 = 0);  -- Only if not already propagated

    GET DIAGNOSTICS _count = ROW_COUNT;
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- 10c. propagate_all_muted_parents (finalization)
-- Full propagation pass for ALL community-muted posts. Used at finalization
-- after indexes are recreated, replacing per-batch propagation which is too
-- expensive during MASSIVE_WITHOUT_INDEXES (no parent_id index → full seq scan).
-- It walks the tree one level at a time and updates the posts it found by id, so
-- every statement is planned from the real size of its id array. A recursive CTE
-- is planned from guesses (10x its seed per level, 0.5% of hive_posts for
-- muted_reasons & 1 = 0, which nearly every post matches), which can turn a level,
-- or the UPDATE's join, into a hash over a seq scan of all of hive_posts.
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.propagate_all_muted_parents()
RETURNS INT AS $function$
DECLARE
    _level INT[];
    _descendants INT[] := '{}';
    _count INT;
BEGIN
    -- Seed: ALL posts muted by community moderation
    _level := ARRAY(
        SELECT hp.id
        FROM hivemind_app.hive_posts hp
        WHERE hp.is_muted = true
          AND hp.muted_reasons & 1 = 1  -- MUTED_COMMUNITY_MODERATION
          AND hp.counter_deleted = 0
    );

    -- Direct children of the level above, through hive_posts_parent_id_id_idx
    WHILE cardinality(_level) > 0 LOOP
        _level := ARRAY(
            SELECT child.id
            FROM hivemind_app.hive_posts child
            WHERE child.parent_id = ANY(_level)
              AND child.counter_deleted = 0
        );
        _descendants := _descendants || _level;
    END LOOP;

    UPDATE hivemind_app.hive_posts hp
    SET is_muted = true,
        muted_reasons = hp.muted_reasons | 4  -- add MUTED_PARENT bit
    WHERE hp.id = ANY(_descendants)
      AND hp.muted_reasons & 1 = 0  -- Don't modify the root muted posts themselves
      AND (hp.is_muted = false OR hp.muted_reasons & 4 = 0);

    GET DIAGNOSTICS _count = ROW_COUNT;
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 11. Notification Flush Functions (Phase 6)
-- ============================================================================

-- Whether _follower had _following on list _list (1: muted, 2: follow_muted) at the end
-- of block _block of the last follows phase; NULL when that phase did not change the pair.
CREATE OR REPLACE FUNCTION hivemind_app.batch_mute_state(
    _list SMALLINT, _follower INT, _following INT, _block INT
) RETURNS BOOLEAN AS $$
    SELECT c.is_set
    FROM hivemind_app._batch_mute_changes c
    WHERE c.follower = _follower AND c.list = _list AND c.following = _following
      AND c.block_num <= _block
    ORDER BY c.block_num DESC, c.op_seq DESC
    LIMIT 1;
$$ LANGUAGE sql STABLE;

-- The notification writers' mute filter at the end of block _block of the last follows
-- phase: true when _dst muted _src, or follows muted lists and every one of them mutes
-- _src (what their joins of muted, follow_muted and muted again keep out). A writer calls
-- it only when that phase changed a list the filter reads (_dst's muted or follow_muted,
-- or a mute of _src): otherwise the lists as they stand are those at the end of every
-- block of the batch, and its joins apply.
CREATE OR REPLACE FUNCTION hivemind_app.notification_muted_at(_dst INT, _src INT, _block INT)
RETURNS BOOLEAN AS $$
    WITH lists AS (
        SELECT f.following,
               COALESCE(hivemind_app.batch_mute_state(1::SMALLINT, f.following, _src, _block),
                        EXISTS (SELECT 1 FROM hivemind_app.muted m
                                WHERE m.follower = f.following AND m.following = _src)) AS mutes_src
        FROM (
            SELECT fm.following FROM hivemind_app.follow_muted fm WHERE fm.follower = _dst
            UNION
            SELECT c.following FROM hivemind_app._batch_mute_changes c WHERE c.follower = _dst AND c.list = 2
        ) f
        WHERE COALESCE(hivemind_app.batch_mute_state(2::SMALLINT, _dst, f.following, _block),
                       EXISTS (SELECT 1 FROM hivemind_app.follow_muted fm
                               WHERE fm.follower = _dst AND fm.following = f.following))
    )
    SELECT COALESCE(hivemind_app.batch_mute_state(1::SMALLINT, _dst, _src, _block),
                    EXISTS (SELECT 1 FROM hivemind_app.muted m WHERE m.follower = _dst AND m.following = _src))
        OR (EXISTS (SELECT 1 FROM lists) AND NOT EXISTS (SELECT 1 FROM lists l WHERE NOT l.mutes_src));
$$ LANGUAGE sql STABLE;

-- 11a. flush_vote_notifications_for_blocks
CREATE OR REPLACE FUNCTION hivemind_app.flush_vote_notifications_for_blocks(
    _first_block INT, _last_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
    _min_block INT;
BEGIN
    _min_block := hivemind_app.block_before_irreversible('90 days');

    -- Skip if all blocks are outside notification window
    IF _last_block <= _min_block THEN
        RETURN 0;
    END IF;

    INSERT INTO hivemind_app.hive_notification_cache
    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
    SELECT
        hivemind_app.notification_id(hn.last_update, 17, hn.counter::INT) AS id,
        hn.block_num, 17, hn.last_update, hn.src, hn.dst, hn.post_id, hn.post_id,
        hn.score,
        hivemind_app.format_vote_value_payload(hn.vote_value),
        '', ''
    FROM (
        SELECT
            hv.last_update,
            -- Counter must be 2*N to match old Python behavior: vote_op increments counter,
            -- then ecv_op increments again, so each vote uses 2 counter slots.
            2 * ROW_NUMBER() OVER (PARTITION BY hv.block_num ORDER BY hv.id) AS counter,
            hv.block_num,
            hv.voter_id AS src,
            hp.author_id AS dst,
            hp.id AS post_id,
            hv.rshares,
            hivemind_app.calculate_value_of_vote_on_post(
                hp.payout + hp.pending_payout, hp.vote_rshares, hv.rshares
            ) AS vote_value,
            hivemind_app.calculate_notify_vote_score(
                hp.payout + hp.pending_payout, hp.abs_rshares, hv.rshares
            ) AS score
        FROM hivemind_app.hive_votes hv
        JOIN hivemind_app.hive_posts hp ON hv.post_id = hp.id
        LEFT JOIN hivemind_app.muted m ON m.follower = hp.author_id AND m.following = hv.voter_id
        LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = hp.author_id
        LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = hv.voter_id
        WHERE hv.block_num BETWEEN _first_block AND _last_block
          AND hv.block_num > _min_block
          AND hp.block_num > hivemind_app.block_before_head('97 days'::interval)
          AND hp.counter_deleted = 0
          AND m.follower IS NULL AND mi.following IS NULL
    ) hn
    WHERE hn.score >= 0
      AND hn.src IS DISTINCT FROM hn.dst
      AND hn.rshares >= 10e9
      AND hn.vote_value >= 0.02
    ORDER BY hn.block_num, hn.last_update, hn.src, hn.dst
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS _count = ROW_COUNT;
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- Helper: compute hivemind reputation score for a single account (index lookup).
CREATE OR REPLACE FUNCTION hivemind_app.reputation_score(_haf_account_id INT)
RETURNS INT AS $$
    SELECT (GREATEST(LOG(10, ABS(nullif(ar.reputation, 0))) - 9, 0)
            * CASE WHEN ar.reputation < 0 THEN -1 ELSE 1 END * 7.5 + 25)::INT
    FROM reptracker_app.account_reputations ar
    WHERE ar.account_id = _haf_account_id;
$$ LANGUAGE sql STABLE;


-- True while a batch of the initial massive sync runs: a batch is in flight
-- (_batch_queue holds its range; live sync leaves it empty) and no finalization
-- has completed yet (hive_state still holds its seed). reptracker syncs beside
-- that sync, so a source's reputation at flush time is not its final one: the
-- writers of reputation-scored notifications (types 11-16) then keep a row
-- whatever its score, and finalization (_finish_reputation_notification_scores)
-- rescores the rows from final reputations and deletes those scoring <= 0.
CREATE OR REPLACE FUNCTION hivemind_app.reputation_notification_cut_deferred()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (SELECT 1 FROM hivemind_app._batch_queue)
       AND (SELECT last_completed_block_num FROM hivemind_app.hive_state) <= 1;
$$ LANGUAGE sql STABLE;


-- 11b. flush_post_notifications_for_blocks
CREATE OR REPLACE FUNCTION hivemind_app.flush_post_notifications_for_blocks(
    _first_block INT, _last_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
    _min_block INT;
    _cut_deferred BOOLEAN;
BEGIN
    _min_block := hivemind_app.block_before_irreversible('90 days');
    _cut_deferred := hivemind_app.reputation_notification_cut_deferred();

    IF _last_block <= _min_block THEN
        RETURN 0;
    END IF;

    -- Find new comments in this batch from _post_results_b (Phase 3's results, handed to
    -- Stage B). Uses the staging table instead of scanning hive_posts by block_num_created
    -- (which has no index during MASSIVE_WITHOUT_INDEXES). Block dates come from HAF's
    -- table, not the context's blocks_view, which the next batch's iteration recreates.
    WITH new_comments AS (
        SELECT
            pr.post_id,
            pr.author_id AS src,
            pr.parent_author_id AS dst,
            pr.parent_id AS dst_post_id,
            pr.depth,
            pr.block_num,
            hb.created_at,
            ROW_NUMBER() OVER (PARTITION BY pr.block_num ORDER BY pr.post_id) AS counter
        FROM hivemind_app._post_results_b pr
        JOIN hafd.blocks hb ON hb.num = pr.block_num - 1
        WHERE pr.is_new_post = true
          AND pr.depth > 0
    )
    INSERT INTO hivemind_app.hive_notification_cache
    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
    SELECT DISTINCT
        hivemind_app.notification_id(nc.created_at, CASE WHEN nc.depth = 1 THEN 12 ELSE 13 END, nc.counter::INT),
        nc.block_num,
        CASE WHEN nc.depth = 1 THEN 12 ELSE 13 END,
        nc.created_at,
        nc.src,
        nc.dst,
        nc.dst_post_id,
        nc.post_id,
        COALESCE(hivemind_app.reputation_score(ha.id), 25),
        '', '', ''
    FROM new_comments nc
    JOIN hivemind_app.hive_accounts ha ON nc.src = ha.id
    LEFT JOIN hivemind_app.muted m ON m.follower = nc.dst AND m.following = nc.src
    LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = nc.dst
    LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = nc.src
    -- mutes filter each notification as they stood at the end of its block (notification_muted_at)
    LEFT JOIN (SELECT DISTINCT c.follower FROM hivemind_app._batch_mute_changes c) mcd ON mcd.follower = nc.dst
    LEFT JOIN (SELECT DISTINCT c.following FROM hivemind_app._batch_mute_changes c WHERE c.list = 1) mcs ON mcs.following = nc.src
    WHERE nc.block_num > _min_block
      AND (_cut_deferred OR COALESCE(hivemind_app.reputation_score(ha.id), 25) > 0)
      AND nc.src IS DISTINCT FROM nc.dst
      AND CASE WHEN mcd.follower IS NOT NULL OR mcs.following IS NOT NULL
               THEN NOT hivemind_app.notification_muted_at(nc.dst, nc.src, nc.block_num)
               ELSE m.follower IS NULL AND mi.following IS NULL END
    ORDER BY nc.block_num, nc.created_at, nc.src, nc.dst, nc.dst_post_id, nc.post_id
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS _count = ROW_COUNT;
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- 11c. flush_follow_notifications_for_blocks
CREATE OR REPLACE FUNCTION hivemind_app.flush_follow_notifications_for_blocks(
    _first_block INT, _last_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
    _min_block INT;
    _cut_deferred BOOLEAN;
BEGIN
    _min_block := hivemind_app.block_before_irreversible('90 days');
    _cut_deferred := hivemind_app.reputation_notification_cut_deferred();

    IF _last_block <= _min_block THEN
        RETURN 0;
    END IF;

    -- Follow notifications use the events staging table populated by process_follows_for_blocks().
    -- This tracks every follow event (including re-follows after unfollows) rather than just
    -- the final state from the follows table.

    WITH new_follows AS (
        SELECT
            ha_f.id AS follower,
            ha_g.id AS following,
            fe.block_num,
            hb.created_at,
            ROW_NUMBER() OVER (PARTITION BY fe.block_num ORDER BY fe.op_seq) AS counter
        FROM hivemind_app._follow_notification_events fe
        JOIN hivemind_app.hive_accounts ha_f ON ha_f.name = fe.follower_name
        JOIN hivemind_app.hive_accounts ha_g ON ha_g.name = fe.following_name
        JOIN hafd.blocks hb ON hb.num = fe.block_num - 1
        WHERE fe.block_num BETWEEN _first_block AND _last_block
    )
    INSERT INTO hivemind_app.hive_notification_cache
    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
    SELECT DISTINCT
        hivemind_app.notification_id(nf.created_at, 15, nf.counter::INT),
        nf.block_num, 15, nf.created_at,
        nf.follower, nf.following,
        NULL::INTEGER, NULL::INTEGER,
        COALESCE(hivemind_app.reputation_score(nf.follower), 25),
        '', '', ''
    FROM new_follows nf
    LEFT JOIN hivemind_app.muted m ON m.follower = nf.following AND m.following = nf.follower
    LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = nf.following
    LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = nf.follower
    -- mutes filter each notification as they stood at the end of its block (notification_muted_at)
    LEFT JOIN (SELECT DISTINCT c.follower FROM hivemind_app._batch_mute_changes c) mcd ON mcd.follower = nf.following
    LEFT JOIN (SELECT DISTINCT c.following FROM hivemind_app._batch_mute_changes c WHERE c.list = 1) mcs ON mcs.following = nf.follower
    WHERE nf.block_num > _min_block
      AND (_cut_deferred OR COALESCE(hivemind_app.reputation_score(nf.follower), 25) > 0)
      AND nf.follower IS DISTINCT FROM nf.following
      AND CASE WHEN mcd.follower IS NOT NULL OR mcs.following IS NOT NULL
               THEN NOT hivemind_app.notification_muted_at(nf.following, nf.follower, nf.block_num)
               ELSE m.follower IS NULL AND mi.following IS NULL END
    ORDER BY nf.block_num, nf.created_at, nf.follower, nf.following
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS _count = ROW_COUNT;
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- 11d. flush_reblog_notifications_for_blocks
CREATE OR REPLACE FUNCTION hivemind_app.flush_reblog_notifications_for_blocks(
    _first_block INT, _last_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
    _min_block INT;
    _cut_deferred BOOLEAN;
BEGIN
    _min_block := hivemind_app.block_before_irreversible('90 days');
    _cut_deferred := hivemind_app.reputation_notification_cut_deferred();

    IF _last_block <= _min_block THEN
        RETURN 0;
    END IF;

    WITH new_reblogs AS (
        SELECT
            hr.blogger_id AS src,
            hp.author_id AS dst,
            hp.parent_id AS dst_post_id,
            hp.id AS post_id,
            hr.block_num,
            hr.created_at,
            ROW_NUMBER() OVER (PARTITION BY hr.block_num ORDER BY hr.id) AS counter
        FROM hivemind_app.hive_reblogs hr
        JOIN hivemind_app.hive_posts hp ON hr.post_id = hp.id
        WHERE hr.block_num BETWEEN _first_block AND _last_block
    )
    INSERT INTO hivemind_app.hive_notification_cache
    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
    SELECT DISTINCT
        hivemind_app.notification_id(nr.created_at, 14, nr.counter::INT),
        nr.block_num, 14, nr.created_at,
        nr.src, nr.dst, nr.dst_post_id, nr.post_id,
        COALESCE(hivemind_app.reputation_score(ha.id), 25),
        '', '', ''
    FROM new_reblogs nr
    JOIN hivemind_app.hive_accounts ha ON nr.src = ha.id
    LEFT JOIN hivemind_app.muted m ON m.follower = nr.dst AND m.following = nr.src
    LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = nr.dst
    LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = nr.src
    -- mutes filter each notification as they stood at the end of its block (notification_muted_at)
    LEFT JOIN (SELECT DISTINCT c.follower FROM hivemind_app._batch_mute_changes c) mcd ON mcd.follower = nr.dst
    LEFT JOIN (SELECT DISTINCT c.following FROM hivemind_app._batch_mute_changes c WHERE c.list = 1) mcs ON mcs.following = nr.src
    WHERE nr.block_num > _min_block
      AND (_cut_deferred OR COALESCE(hivemind_app.reputation_score(ha.id), 25) > 0)
      AND nr.src IS DISTINCT FROM nr.dst
      AND CASE WHEN mcd.follower IS NOT NULL OR mcs.following IS NOT NULL
               THEN NOT hivemind_app.notification_muted_at(nr.dst, nr.src, nr.block_num)
               ELSE m.follower IS NULL AND mi.following IS NULL END
    ORDER BY nr.block_num, nr.created_at, nr.src, nr.dst, nr.dst_post_id, nr.post_id
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS _count = ROW_COUNT;
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- Server-side wrapper: process_batch_phases_1_to_3a
-- Runs Phases 1 through 3a in a single function call, eliminating ~8
-- Python→DB round-trips (START TRANSACTION/COMMIT pairs for each sub-phase).
-- Within a single function, all statements share the same snapshot and can
-- see each other's writes without explicit COMMIT.
-- Returns the post_staging_result set needed by Python for body merging.
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_batch_phases_1_to_3a(
    _first_block INT,
    _last_block INT,
    _community_support_start_block INT
) RETURNS SETOF hivemind_app.post_staging_result AS $function$
BEGIN
    -- Phase 1: Load staging table
    PERFORM hivemind_app.load_ops_staging(_first_block, _last_block);

    -- Phase 2: Account registration
    PERFORM hivemind_app.process_accounts_from_staging(_community_support_start_block);

    -- Phase 2.5: Community state changes (subscribe, setRole, updateProps)
    PERFORM hivemind_app.process_community_from_staging(_community_support_start_block, 1);

    -- Phase 3: Post/comment processing
    -- Must return results for Python body merging (Phase 3b)
    RETURN QUERY SELECT * FROM hivemind_app.process_posts_from_staging(_community_support_start_block);

    -- Phase 3a: Community post-targeting ops (mutePost, unmutePost, pinPost)
    PERFORM hivemind_app.process_community_from_staging(_community_support_start_block, 2);

    -- Phase 3a continued: Propagate MUTED_PARENT to children of newly-muted posts
    PERFORM hivemind_app.propagate_muted_parent_for_batch(_first_block, _last_block);
END
$function$ LANGUAGE plpgsql VOLATILE;
