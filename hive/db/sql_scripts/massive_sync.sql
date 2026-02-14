--- Pure SQL Massive Sync Functions for Hivemind ---
--- Replaces the Python dispatch loop with SQL functions that read from a staging table ---

-- ============================================================================
-- 1. Staging Table DDL
-- ============================================================================

-- Sequence for community op notification counter (avoids collisions across ops)
CREATE SEQUENCE IF NOT EXISTS hivemind_app.community_op_counter;

CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._ops_staging (
    id          BIGINT NOT NULL,       -- HAF operation ID (ordering)
    block_num   INT NOT NULL,
    block_date  TIMESTAMP NOT NULL,
    op_type_id  SMALLINT NOT NULL,
    val         JSONB                  -- body->'value' (pre-extracted)
);

-- Drop indexes if they exist (idempotent)
DROP INDEX IF EXISTS hivemind_app._ops_staging_op_type_id_idx;
DROP INDEX IF EXISTS hivemind_app._ops_staging_block_num_id_idx;

CREATE INDEX _ops_staging_op_type_id_idx ON hivemind_app._ops_staging (op_type_id);
CREATE INDEX _ops_staging_block_num_id_idx ON hivemind_app._ops_staging (block_num, id);

-- Persistent unlogged tables for process_posts_from_staging (avoids PL/pgSQL stale OID with temp tables)
CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._comment_staging (
    seq_id      INT NOT NULL,
    is_first    BOOLEAN NOT NULL,
    block_num   INT NOT NULL,
    block_date  TIMESTAMP NOT NULL,
    author      TEXT,
    permlink    TEXT,
    parent_author TEXT,
    parent_permlink TEXT,
    op_body     JSONB
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


-- Staging table for follow notification events (populated by process_follows_for_blocks,
-- read by flush_follow_notifications_for_blocks). Tracks individual follow events
-- including re-follows after unfollow, which the follows table (final state) doesn't preserve.
CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app._follow_notification_events (
    follower_name TEXT NOT NULL,
    following_name TEXT NOT NULL,
    block_num     INT NOT NULL,
    op_seq        BIGINT NOT NULL
);


-- ============================================================================
-- Helper: safe_parse_jsonb — parse text as jsonb, return NULL on failure
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.safe_parse_jsonb(_text TEXT)
RETURNS JSONB AS $function$
BEGIN
    IF _text IS NULL THEN RETURN NULL; END IF;
    RETURN _text::jsonb;
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
    TRUNCATE hivemind_app._ops_staging;
    TRUNCATE hivemind_app._follow_notification_events;

    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    SELECT ho.id, ho.block_num,
           -- Old Python used _head_block_date (previous block's date) for regular ops,
           -- but the current block's date for virtual ops (payouts processed in _process_vops_flat
           -- received date=block_dates[block_num]). Match that behavior.
           CASE WHEN ho.op_type_id >= 50
               THEN hb.created_at
               ELSE COALESCE(hb_prev.created_at, hb.created_at)
           END AS block_date,
           ho.op_type_id, ho.body->'value'
    FROM hivemind_app.operations_view ho
    JOIN hivemind_app.blocks_view hb ON hb.num = ho.block_num
    LEFT JOIN hivemind_app.blocks_view hb_prev ON hb_prev.num = ho.block_num - 1
    WHERE ho.block_num BETWEEN _first_block AND _last_block
      AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43,51,53,61,72,73)
      AND (ho.op_type_id != 18
        OR ho.custom_json_type_id IN (
            SELECT cjt.id FROM hafd.custom_json_types cjt
            WHERE cjt.custom_json_id IN ('follow', 'reblog', 'community', 'notify')
        ));

    ANALYZE hivemind_app._ops_staging;
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
        INSERT INTO hivemind_app.hive_accounts (name, created_at, posting_json_metadata, json_metadata, haf_id)
        SELECT ti.acct_name, ti.first_block_date, ti.posting_json_metadata, ti.json_metadata,
               (SELECT av.id FROM hivemind_app.accounts_view av WHERE av.name = ti.acct_name)
        FROM to_insert ti
        ORDER BY ti.first_op_id  -- Match old Python registration order (by HAF op id)
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

CREATE OR REPLACE FUNCTION hivemind_app.process_votes_from_staging(
    _last_safe_cashout_block INT DEFAULT 0
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    -- Process vote ops (type 0) and effective_comment_vote ops (type 72)
    -- from the staging table.
    --
    -- Within a batch, for the same (voter, author, permlink):
    --   - type 0: keep last vote_percent and last_update
    --   - type 72: keep last weight, rshares, is_effective
    --
    -- Deduplication: for the same voter/author/permlink, we aggregate:
    --   - From type 0 (VOTE): vote_percent, last_update from the LAST occurrence
    --   - From type 72 (ECV): weight, rshares from the LAST occurrence
    --   - num_changes = count of effective_comment_vote ops

    -- Step 1: Collect and deduplicate vote data
    CREATE TEMP TABLE _vote_batch ON COMMIT DROP AS
    WITH vote_ops AS (
        -- Regular votes (type 0)
        SELECT
            s.id,
            s.block_num,
            s.val->>'voter' AS voter,
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            (s.val->>'weight')::INT AS vote_percent,
            s.block_date AS last_update,
            0::NUMERIC AS weight,
            0::BIGINT AS rshares,
            FALSE AS is_effective
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 0
    ),
    ecv_ops AS (
        -- Effective comment vote ops (type 72)
        SELECT
            s.id,
            s.block_num,
            s.val->>'voter' AS voter,
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            0 AS vote_percent,
            '1970-01-01'::TIMESTAMP AS last_update,
            (s.val->>'weight')::NUMERIC AS weight,
            CASE WHEN s.block_num < 905693
                THEN (s.val->>'rshares')::BIGINT * 1000000
                ELSE (s.val->>'rshares')::BIGINT
            END AS rshares,
            TRUE AS is_effective
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 72
    ),
    all_vote_data AS (
        SELECT * FROM vote_ops
        UNION ALL
        SELECT * FROM ecv_ops
    ),
    -- For each (voter, author, permlink), take the last vote_percent/last_update from type 0
    -- and the last weight/rshares from type 72
    last_vote AS (
        SELECT DISTINCT ON (voter, author, permlink)
            voter, author, permlink, vote_percent, last_update, block_num
        FROM vote_ops
        ORDER BY voter, author, permlink, id DESC
    ),
    last_ecv AS (
        SELECT DISTINCT ON (voter, author, permlink)
            voter, author, permlink, weight, rshares, block_num,
            count(*) OVER (PARTITION BY voter, author, permlink) - 1 AS num_changes
        FROM ecv_ops
        ORDER BY voter, author, permlink, id DESC
    ),
    -- Merge: combine vote data with effective vote data
    merged AS (
        SELECT
            COALESCE(v.voter, e.voter) AS voter,
            COALESCE(v.author, e.author) AS author,
            COALESCE(v.permlink, e.permlink) AS permlink,
            COALESCE(v.vote_percent, 0) AS vote_percent,
            COALESCE(v.last_update, '1970-01-01'::TIMESTAMP) AS last_update,
            COALESCE(e.weight, 0) AS weight,
            COALESCE(e.rshares, 0) AS rshares,
            (e.voter IS NOT NULL) AS is_effective,
            COALESCE(e.num_changes, 0)::INT AS num_changes,
            GREATEST(COALESCE(v.block_num, 0), COALESCE(e.block_num, 0)) AS block_num
        FROM last_vote v
        FULL OUTER JOIN last_ecv e
            ON v.voter = e.voter AND v.author = e.author AND v.permlink = e.permlink
    )
    SELECT
        m.voter,
        ha_voter.id AS voter_id,
        m.author,
        ha_author.id AS author_id,
        m.permlink,
        m.vote_percent,
        m.last_update,
        m.weight,
        m.rshares,
        m.is_effective,
        m.num_changes,
        m.block_num
    FROM merged m
    JOIN hivemind_app.hive_accounts ha_voter ON ha_voter.name = m.voter
    JOIN hivemind_app.hive_accounts ha_author ON ha_author.name = m.author;

    -- Step 2: Insert/update votes with resolved post_id
    WITH vote_with_post AS (
        SELECT
            vb.*,
            hp.id AS post_id,
            hpd.id AS permlink_id
        FROM _vote_batch vb
        JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = vb.permlink
        JOIN hivemind_app.hive_posts hp
            ON hp.author_id = vb.author_id
            AND hp.permlink_id = hpd.id
            AND hp.counter_deleted = 0
    ),
    upserted AS (
        INSERT INTO hivemind_app.hive_votes
            (post_id, voter_id, author_id, permlink_id, weight, rshares,
             vote_percent, last_update, num_changes, block_num, is_effective)
        SELECT
            vwp.post_id, vwp.voter_id, vwp.author_id, vwp.permlink_id,
            vwp.weight, vwp.rshares, vwp.vote_percent, vwp.last_update,
            vwp.num_changes, vwp.block_num, vwp.is_effective
        FROM vote_with_post vwp
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
            num_changes = hivemind_app.hive_votes.num_changes + EXCLUDED.num_changes + 1,
            block_num = EXCLUDED.block_num
        WHERE hivemind_app.hive_votes.voter_id = EXCLUDED.voter_id
          AND hivemind_app.hive_votes.author_id = EXCLUDED.author_id
          AND hivemind_app.hive_votes.permlink_id = EXCLUDED.permlink_id
        RETURNING post_id
    )
    SELECT count(*) INTO _count FROM upserted;

    DROP TABLE IF EXISTS _vote_batch;

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 5. process_reblogs_from_staging()
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_reblogs_from_staging()
RETURNS INT AS $function$
DECLARE
    _count INT := 0;
BEGIN
    -- Extract reblog custom_json ops from staging (type 18, custom_json_id = 'reblog' or 'follow')
    -- Reblogs come as custom_json with id='follow' or id='reblog' containing ["reblog", {...}]

    CREATE TEMP TABLE _reblog_ops ON COMMIT DROP AS
    WITH raw_ops AS (
        SELECT
            s.id,
            s.block_num,
            s.block_date,
            s.val AS val
        FROM hivemind_app._ops_staging s
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
            hivemind_app.safe_parse_jsonb(ro.val->>'json') AS inner_json
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

    -- Determine final action per (author, permlink, account): last op wins
    -- This handles create→delete→create within the same batch correctly.
    CREATE TEMP TABLE _reblog_final ON COMMIT DROP AS
    SELECT DISTINCT ON (author, permlink, account)
        id, account, author, permlink, block_date, block_num, is_delete
    FROM _reblog_ops
    ORDER BY author, permlink, account, id DESC;

    -- Process deletes: delete entries where ANY delete exists in this batch
    -- (covers entries from previous batches that need cleanup)
    PERFORM hivemind_app.delete_reblog_feed_cache(
        ro.author::VARCHAR, ro.permlink::VARCHAR, ro.account::VARCHAR
    )
    FROM (SELECT DISTINCT author, permlink, account FROM _reblog_ops WHERE is_delete) ro;

    -- Process creates: only insert where the FINAL action is a create
    WITH deduped AS (
        SELECT account, author, permlink, block_date, block_num
        FROM _reblog_final
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
            ON hp.author_id = ha.id AND hp.permlink_id = hpd.id AND hp.counter_deleted = 0
    )
    INSERT INTO hivemind_app.hive_reblogs (blogger_id, post_id, created_at, block_num)
    SELECT blogger_id, post_id, created_at, block_num FROM validated
    ON CONFLICT ON CONSTRAINT hive_reblogs_ux1 DO NOTHING;

    GET DIAGNOSTICS _count = ROW_COUNT;

    DROP TABLE IF EXISTS _reblog_ops;

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
    -- Deduplicate: per account, last update wins (highest op id)
    -- Type 10: json_metadata always updated, posting_json_metadata only if present
    -- Type 43: both json_metadata and posting_json_metadata always updated

    WITH deduped AS (
        -- For each account, keep the last update op
        SELECT DISTINCT ON (val->>'account')
            s.id,
            s.op_type_id,
            s.val->>'account' AS account_name,
            -- posting_json_metadata: only type 43 (ACCOUNT_UPDATE_2) allows changing it
            CASE
                WHEN s.op_type_id = 43 THEN COALESCE(s.val->>'posting_json_metadata', '')
                ELSE NULL  -- type 10 doesn't change posting_json_metadata
            END AS posting_json_metadata,
            COALESCE(s.val->>'json_metadata', '') AS json_metadata,
            -- Track if this is type 43 (allows posting_json_metadata change)
            (s.op_type_id = 43) AS allow_change_posting
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id IN (10, 43)
        ORDER BY val->>'account', s.id DESC
    )
    UPDATE hivemind_app.hive_accounts ha
    SET
        posting_json_metadata = CASE
            WHEN d.allow_change_posting THEN d.posting_json_metadata
            ELSE ha.posting_json_metadata
        END,
        json_metadata = d.json_metadata
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
            hivemind_app.safe_parse_jsonb(s.val->>'json') AS inner_json
        FROM hivemind_app._ops_staging s
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
                THEN COALESCE(
                    -- Use explicit date if provided, otherwise use block_date
                    LEAST((no.inner_json->1->>'date')::TIMESTAMP, no.block_date),
                    no.block_date
                )
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
    -- Collect payout virtual ops (types 51, 53, 61, 72) from staging
    -- Aggregate per (author, permlink): combine AUTHOR_REWARD, COMMENT_REWARD,
    -- COMMENT_PAYOUT_UPDATE, EFFECTIVE_COMMENT_VOTE values
    --
    -- When COMMENT_REWARD exists for a post, EFFECTIVE_COMMENT_VOTE payout data
    -- is discarded (nullified).

    WITH payout_ops AS (
        SELECT
            s.id,
            s.block_num,
            s.block_date,
            s.op_type_id,
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            s.val
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id IN (51, 53, 61, 72)
    ),
    -- Check which (author, permlink) pairs have COMMENT_REWARD (type 53)
    has_comment_reward AS (
        SELECT DISTINCT author, permlink
        FROM payout_ops WHERE op_type_id = 53
    ),
    -- COMMENT_PAYOUT_UPDATE (type 61) - "final" payout marker
    cpu_data AS (
        SELECT DISTINCT ON (author, permlink)
            author, permlink, block_date AS payout_date
        FROM payout_ops WHERE op_type_id = 61
        ORDER BY author, permlink, id DESC
    ),
    -- AUTHOR_REWARD (type 51)
    ar_data AS (
        SELECT DISTINCT ON (author, permlink)
            author, permlink,
            (val->'hive_payout'->>'amount')::BIGINT AS author_rewards_hive,
            (val->'hbd_payout'->>'amount')::BIGINT AS author_rewards_hbd,
            (val->'vesting_payout'->>'amount')::BIGINT AS author_rewards_vests,
            block_date AS payout_date
        FROM payout_ops WHERE op_type_id = 51
        ORDER BY author, permlink, id DESC
    ),
    -- COMMENT_REWARD (type 53)
    cr_data AS (
        SELECT DISTINCT ON (author, permlink)
            author, permlink,
            (val->>'author_rewards')::BIGINT AS author_rewards,
            val->'total_payout_value' AS total_payout_value,
            val->'curator_payout_value' AS curator_payout_value,
            val->'beneficiary_payout_value' AS beneficiary_payout_value,
            block_date AS payout_date
        FROM payout_ops WHERE op_type_id = 53
        ORDER BY author, permlink, id DESC
    ),
    -- EFFECTIVE_COMMENT_VOTE (type 72) - only if NOT safe cashout and no COMMENT_REWARD
    ecv_data AS (
        SELECT DISTINCT ON (po.author, po.permlink)
            po.author, po.permlink,
            po.val->'pending_payout' AS pending_payout_json,
            (po.val->>'total_vote_weight')::NUMERIC AS total_vote_weight
        FROM payout_ops po
        WHERE po.op_type_id = 72
          AND po.block_num > _last_safe_cashout_block
          AND NOT EXISTS (
              SELECT 1 FROM has_comment_reward hcr
              WHERE hcr.author = po.author AND hcr.permlink = po.permlink
          )
        ORDER BY po.author, po.permlink, po.id DESC
    ),
    -- Collect all unique (author, permlink) pairs that have any payout data
    all_keys AS (
        SELECT author, permlink FROM cpu_data
        UNION
        SELECT author, permlink FROM ar_data
        UNION
        SELECT author, permlink FROM cr_data
        UNION
        SELECT author, permlink FROM ecv_data
    ),
    -- Merge all payout data
    merged AS (
        SELECT
            ak.author, ak.permlink,
            ha.id AS author_id,
            -- From COMMENT_PAYOUT_UPDATE
            cpu.payout_date AS cpu_payout_date,
            -- From AUTHOR_REWARD
            ar.author_rewards_hive,
            ar.author_rewards_hbd,
            ar.author_rewards_vests,
            -- From COMMENT_REWARD
            cr.author_rewards,
            cr.total_payout_value,
            cr.curator_payout_value,
            cr.beneficiary_payout_value,
            cr.payout_date AS cr_payout_date,
            -- From EFFECTIVE_COMMENT_VOTE (only if no COMMENT_REWARD)
            ecv.pending_payout_json,
            ecv.total_vote_weight
        FROM all_keys ak
        JOIN hivemind_app.hive_accounts ha ON ha.name = ak.author
        LEFT JOIN cpu_data cpu ON cpu.author = ak.author AND cpu.permlink = ak.permlink
        LEFT JOIN ar_data ar ON ar.author = ak.author AND ar.permlink = ak.permlink
        LEFT JOIN cr_data cr ON cr.author = ak.author AND cr.permlink = ak.permlink
        LEFT JOIN ecv_data ecv ON ecv.author = ak.author AND ecv.permlink = ak.permlink
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
        author_rewards = COALESCE(m.author_rewards, 0) + hp.author_rewards,
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
        pending_payout = COALESCE(
            CASE
                WHEN m.total_payout_value IS NOT NULL THEN 0  -- COMMENT_REWARD zeroes pending
                WHEN m.cpu_payout_date IS NOT NULL THEN 0     -- COMMENT_PAYOUT_UPDATE zeroes pending
                WHEN m.pending_payout_json IS NOT NULL THEN
                    hivemind_app.sbd_amount_from_json(m.pending_payout_json)::DECIMAL(10,3)
                ELSE NULL
            END,
            hp.pending_payout
        ),
        payout_at = COALESCE(m.cpu_payout_date, hp.payout_at),
        last_payout_at = COALESCE(
            m.cr_payout_date,
            m.cpu_payout_date,
            hp.last_payout_at
        ),
        cashout_time = CASE
            WHEN m.cpu_payout_date IS NOT NULL THEN 'infinity'::TIMESTAMP
            ELSE hp.cashout_time
        END,
        is_paidout = CASE
            WHEN m.cpu_payout_date IS NOT NULL THEN TRUE
            ELSE hp.is_paidout
        END,
        total_vote_weight = COALESCE(
            CASE
                WHEN m.cpu_payout_date IS NOT NULL THEN 0  -- COMMENT_PAYOUT_UPDATE zeroes it
                ELSE m.total_vote_weight
            END,
            hp.total_vote_weight
        )
    FROM merged m
    JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = m.permlink
    WHERE hp.author_id = m.author_id
      AND hp.permlink_id = hpd.id
      AND hp.counter_deleted = 0;

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


-- ============================================================================
-- 9. process_posts_from_staging()
-- ============================================================================

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
    _wave INT;
    _processed_count INT;
    _remaining INT;
BEGIN
    -- Truncate persistent unlogged staging tables (avoids PL/pgSQL stale OID with temp tables)
    TRUNCATE hivemind_app._comment_staging;
    TRUNCATE hivemind_app._post_results;

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
    INSERT INTO hivemind_app._comment_staging (seq_id, is_first, block_num, block_date, author, permlink, parent_author, parent_permlink, op_body)
    SELECT
        ROW_NUMBER() OVER (ORDER BY s.id)::INT AS seq_id,
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
            WHERE cs.is_first
              AND (cs.parent_author IS NULL OR cs.parent_author = '')
            ORDER BY cs.seq_id
        )
    ) br
    JOIN hivemind_app._comment_staging cs ON cs.seq_id = br.seq_id;

    -- Step 5: Process comments with wave-based resolution (first-occurrence only)
    FOR _wave IN 1..20 LOOP
        -- Count unprocessed first-occurrence comments (not yet in results)
        SELECT count(*) INTO _remaining
        FROM hivemind_app._comment_staging cs
        WHERE cs.is_first
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
                WHERE cs.is_first
                  AND cs.parent_author IS NOT NULL AND cs.parent_author != ''
                  AND NOT EXISTS (SELECT 1 FROM hivemind_app._post_results pr WHERE pr.seq_id = cs.seq_id)
                ORDER BY cs.seq_id
            )
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
    WHERE NOT cs.is_first;

    -- Step 5c: Update updated_at for edit ops
    -- Edits (is_first=false) don't go through the batch functions, so updated_at is
    -- stuck at the creation timestamp. Update it to the last edit's block_date.
    UPDATE hivemind_app.hive_posts hp
    SET updated_at = last_edit.block_date
    FROM (
        SELECT DISTINCT ON (pr.post_id)
            pr.post_id, cs.block_date
        FROM hivemind_app._comment_staging cs
        JOIN hivemind_app._comment_staging cs_first
            ON cs_first.author = cs.author AND cs_first.permlink = cs.permlink AND cs_first.is_first
        JOIN hivemind_app._post_results pr ON pr.seq_id = cs_first.seq_id
        WHERE NOT cs.is_first
        ORDER BY pr.post_id, cs.seq_id DESC
    ) last_edit
    WHERE hp.id = last_edit.post_id;

    -- Step 5d: Process tags for root posts
    -- Tags come from json_metadata.tags array + parent_permlink (category).
    -- Only root posts (parent_author is empty) get tags.
    -- json_metadata can be a JSON string (double-encoded) or an object; handle both.
    -- Malformed json_metadata is silently ignored (matching old Python try/except).
    PERFORM hivemind_app.process_tags_batch(
        ARRAY(
            SELECT ROW(
                base.post_id,
                sub.tag_val::VARCHAR,
                base.is_new_post
            )::hivemind_app.post_tag_input
            FROM (
                SELECT pr.post_id, pr.is_new_post, cs.parent_permlink,
                       hivemind_app.safe_parse_jsonb(cs.op_body->>'json_metadata') AS parsed_md
                FROM hivemind_app._comment_staging cs
                JOIN hivemind_app._post_results pr ON pr.seq_id = cs.seq_id
                WHERE cs.is_first
                  AND (cs.parent_author IS NULL OR cs.parent_author = '')
            ) base
            CROSS JOIN LATERAL (
                SELECT unnest(
                    COALESCE(
                        ARRAY(
                            SELECT jsonb_array_elements_text(base.parsed_md->'tags')
                            WHERE base.parsed_md IS NOT NULL
                              AND base.parsed_md->'tags' IS NOT NULL
                              AND jsonb_typeof(base.parsed_md->'tags') = 'array'
                        ),
                        '{}'::TEXT[]
                    )
                    ||
                    ARRAY[base.parent_permlink]
                ) AS tag_val
            ) sub
        )
    );

    -- Step 6: Process comment_options (type 19) - update hive_posts columns
    WITH co_ops AS (
        SELECT
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
    WHERE hp.author_id = ha.id AND hp.permlink_id = hpd.id;

    -- Step 7: Process deletes (type 17), filtering against ineffective set
    FOR _rec IN
        SELECT
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            s.block_num,
            s.block_date
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 17
          AND NOT ((s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_ineffective_keys))
    LOOP
        PERFORM hivemind_app.delete_hive_post(
            _rec.author::VARCHAR, _rec.permlink::VARCHAR, _rec.block_num, _rec.block_date
        );
    END LOOP;

    -- Step 7b: Handle post recreates after deletes within the same batch
    -- When a post is created, deleted, and re-created in the same batch,
    -- the delete increments counter_deleted but the second create was treated
    -- as an edit (is_first=false). We need to reset counter_deleted=0 for posts
    -- where a comment op exists AFTER the LAST delete for that author/permlink.
    WITH last_delete_per_post AS (
        -- Get the LAST (highest op_id) delete per (author, permlink)
        SELECT DISTINCT ON (s.val->>'author', s.val->>'permlink')
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            s.id AS last_delete_op_id
        FROM hivemind_app._ops_staging s
        WHERE s.op_type_id = 17
          AND NOT ((s.val->>'author') || '/' || (s.val->>'permlink') = ANY(_ineffective_keys))
        ORDER BY s.val->>'author', s.val->>'permlink', s.id DESC
    ),
    recreate_ops AS (
        -- Find the FIRST create op that occurs AFTER the LAST delete
        SELECT DISTINCT ON (ld.author, ld.permlink)
            ld.author,
            ld.permlink,
            s_create.block_num,
            s_create.block_date
        FROM last_delete_per_post ld
        JOIN hivemind_app._ops_staging s_create ON s_create.op_type_id = 1
            AND s_create.val->>'author' = ld.author
            AND s_create.val->>'permlink' = ld.permlink
            AND s_create.id > ld.last_delete_op_id
        ORDER BY ld.author, ld.permlink, s_create.id ASC
    )
    UPDATE hivemind_app.hive_posts hp
    SET counter_deleted = 0,
        block_num = r.block_num,
        active = r.block_date,
        updated_at = r.block_date,
        is_muted = FALSE,
        muted_reasons = 0
    FROM recreate_ops r
    JOIN hivemind_app.hive_accounts ha ON ha.name = r.author
    JOIN hivemind_app.hive_permlink_data hpd ON hpd.permlink = r.permlink
    WHERE hp.author_id = ha.id
      AND hp.permlink_id = hpd.id
      AND hp.counter_deleted > 0
      -- Find the most recently deleted version (highest counter_deleted)
      AND hp.counter_deleted = (
          SELECT MAX(hp2.counter_deleted)
          FROM hivemind_app.hive_posts hp2
          WHERE hp2.author_id = ha.id AND hp2.permlink_id = hpd.id
      );

    -- Step 8: Generate muted post error notifications
    -- When a new post in a community is muted (muted_reasons != 0), generate an 'error'
    -- notification (type 10) for the post author, explaining why it was muted.
    INSERT INTO hivemind_app.hive_notification_cache
        (id, block_num, type_id, score, created_at, src, dst, post_id, dst_post_id,
         community, community_title, payload)
    SELECT
        hivemind_app.notification_id(pr.block_date, 10, pr.seq_id % 4194303),
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
    WHERE pr.is_new_post
      AND pr.muted_reasons IS NOT NULL
      AND pr.muted_reasons != 0
      AND pr.community_id IS NOT NULL
      AND pr.block_num > hivemind_app.block_before_irreversible('90 days')
      AND pr.community_id IS DISTINCT FROM pr.author_id
    ON CONFLICT (src, dst, type_id, post_id, block_num) DO NOTHING;

    -- Return all post results
    RETURN QUERY SELECT * FROM hivemind_app._post_results ORDER BY seq_id;

    -- Tables are truncated at start of next call, no drop needed
    -- comment_staging is truncated at start of next call
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 9b. process_community_op — dispatch a single community custom_json action
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_community_op(
    _auth_account TEXT,
    _action TEXT,
    _data JSONB,
    _date TIMESTAMP,
    _block_num INT,
    _counter_in INT DEFAULT 0
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
BEGIN
    -- Resolve actor
    SELECT id INTO _actor_id FROM hivemind_app.hive_accounts WHERE name = _auth_account;
    IF _actor_id IS NULL THEN RETURN _counter_in; END IF;

    -- Read community name (required for all actions)
    _community_name := _data->>'community';
    IF _community_name IS NULL OR _community_name = '' THEN RETURN _counter_in; END IF;

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
            );
        END IF;
        RETURN _counter_in;
    END IF;

    -- Read action-specific fields
    IF _action IN ('setRole', 'setUserTitle', 'mutePost', 'unmutePost', 'pinPost', 'unpinPost', 'flagPost') THEN
        _account_name := _data->>'account';
        IF _account_name IS NULL OR _account_name = '' THEN RETURN _counter_in; END IF;
        SELECT id INTO _account_id FROM hivemind_app.hive_accounts WHERE name = _account_name;
        IF _account_id IS NULL THEN RETURN _counter_in; END IF;
    END IF;

    IF _action IN ('mutePost', 'unmutePost', 'pinPost', 'unpinPost', 'flagPost') THEN
        _permlink := _data->>'permlink';
        IF _permlink IS NULL OR _permlink = '' THEN RETURN _counter_in; END IF;
    END IF;

    IF _action IN ('mutePost', 'unmutePost', 'flagPost') THEN
        _notes := _data->>'notes';
    END IF;

    -- Get notification threshold
    SELECT hivemind_app.block_before_irreversible('90 days') INTO _notification_first_block;

    -- Dispatch
    CASE _action
        WHEN 'updateProps' THEN
            _props := _data->'props';
            IF _props IS NULL OR jsonb_typeof(_props) != 'object' THEN RETURN _counter_in; END IF;
            SELECT * INTO _result FROM hivemind_app.update_community_props(_actor_id, _community_id, _props);
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
            _role := _data->>'role';
            IF _role IS NULL OR _role = '' THEN RETURN _counter_in; END IF;
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
            IF _result.success AND _block_num > _notification_first_block THEN
                _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                _counter_in := _counter_in + 1;
                INSERT INTO hivemind_app.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                VALUES (
                    hivemind_app.notification_id(_date, 2, _counter_in),
                    _block_num, 2, _date, _actor_id, _account_id, NULL, NULL, _score, _role, _community_name, ''
                );
            END IF;

        WHEN 'setUserTitle' THEN
            _title := COALESCE(TRIM(_data->>'title'), '');
            SELECT * INTO _result FROM hivemind_app.community_set_title(
                _actor_id, _account_id, _community_id, _title, _date
            );
            IF _result.success AND _block_num > _notification_first_block THEN
                _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                _counter_in := _counter_in + 1;
                INSERT INTO hivemind_app.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                VALUES (
                    hivemind_app.notification_id(_date, 4, _counter_in),
                    _block_num, 4, _date, _actor_id, _account_id, NULL, NULL, _score, _title, _community_name, ''
                );
            END IF;

        WHEN 'mutePost' THEN
            SELECT * INTO _result FROM hivemind_app.community_mute_post(
                _actor_id, _community_id, _account_id, _permlink, 1  -- muted_reasons bitmask: bit 0 = community moderation
            );
            IF _result.success AND _block_num > _notification_first_block THEN
                _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                _counter_in := _counter_in + 1;
                INSERT INTO hivemind_app.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                VALUES (
                    hivemind_app.notification_id(_date, 5, _counter_in),
                    _block_num, 5, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                );
            END IF;

        WHEN 'unmutePost' THEN
            SELECT * INTO _result FROM hivemind_app.community_unmute_post(
                _actor_id, _community_id, _account_id, _permlink
            );
            IF _result.success AND _block_num > _notification_first_block THEN
                _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                _counter_in := _counter_in + 1;
                INSERT INTO hivemind_app.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                VALUES (
                    hivemind_app.notification_id(_date, 6, _counter_in),
                    _block_num, 6, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                );
            END IF;

        WHEN 'pinPost' THEN
            SELECT * INTO _result FROM hivemind_app.community_pin_post(
                _actor_id, _community_id, _account_id, _permlink
            );
            IF _result.success AND _block_num > _notification_first_block THEN
                _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                _counter_in := _counter_in + 1;
                INSERT INTO hivemind_app.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                VALUES (
                    hivemind_app.notification_id(_date, 7, _counter_in),
                    _block_num, 7, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                );
            END IF;

        WHEN 'unpinPost' THEN
            SELECT * INTO _result FROM hivemind_app.community_unpin_post(
                _actor_id, _community_id, _account_id, _permlink
            );
            IF _result.success AND _block_num > _notification_first_block THEN
                _score := CASE WHEN _result.is_subscribed THEN 35 ELSE 15 END;
                _counter_in := _counter_in + 1;
                INSERT INTO hivemind_app.hive_notification_cache
                (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
                VALUES (
                    hivemind_app.notification_id(_date, 8, _counter_in),
                    _block_num, 8, _date, _actor_id, _account_id, _result.post_id, _result.post_id, _score, _notes, _community_name, ''
                );
            END IF;

        WHEN 'flagPost' THEN
            SELECT * INTO _result FROM hivemind_app.community_flag_post(
                _actor_id, _community_id, _account_id, _permlink, _community_name
            );
            IF _result.success AND _block_num > _notification_first_block THEN
                SELECT hivemind_app._community_notify_team(
                    _block_num, 9, _actor_id, _community_id, _date, _result.post_id, _result.team_members, _notes, _counter_in
                ) INTO _counter_in;
            END IF;

        ELSE
            RETURN _counter_in;  -- Unknown action
    END CASE;

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

        -- Parse inner JSON
        BEGIN
            _inner_json := (_val->>'json')::jsonb;
        EXCEPTION WHEN OTHERS THEN
            CONTINUE;
        END;

        -- Must be array of length 2: ['action', {data}]
        IF jsonb_typeof(_inner_json) != 'array' OR jsonb_array_length(_inner_json) != 2 THEN
            CONTINUE;
        END IF;

        _action := _inner_json->>0;
        _data := _inner_json->1;

        IF jsonb_typeof(_data) != 'object' THEN
            CONTINUE;
        END IF;

        _is_state_action := _action IN ('subscribe', 'unsubscribe', 'setRole', 'updateProps', 'setUserTitle');

        -- Phase filtering
        IF _phase = 1 THEN
            -- Phase 1: ALL state actions (subscribe, setRole, updateProps, etc.)
            -- These must be applied before posts so that role lookups and community
            -- metadata are correct during post muting decisions.
            IF NOT _is_state_action THEN CONTINUE; END IF;
        END IF;
        IF _phase = 2 THEN
            -- Phase 2: ONLY post-targeting ops (mutePost, pinPost, flagPost, etc.)
            IF _is_state_action THEN CONTINUE; END IF;
        END IF;

        -- Per-block counter for community notifications (resets when block changes)
        IF _rec.block_num != _last_counter_block THEN
            _community_counter := 0;
            _last_counter_block := _rec.block_num;
        END IF;

        -- Dispatch to existing community SQL functions via the Python-equivalent process
        -- This delegates to the existing community.sql functions
        BEGIN
            SELECT hivemind_app.process_community_op(
                _auth_account, _action, _data, _rec.block_date, _rec.block_num, _community_counter
            ) INTO _community_counter;
            _count := _count + 1;
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Community op failed: action=% account=% block=% error=%',
                _action, _auth_account, _rec.block_num, SQLERRM;
        END;
    END LOOP;

    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 11. Notification Flush Functions (Phase 6)
-- ============================================================================

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
        SELECT DISTINCT
            hv.last_update,
            ROW_NUMBER() OVER (PARTITION BY hv.block_num ORDER BY hv.id) AS counter,
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


-- 11b. flush_post_notifications_for_blocks
CREATE OR REPLACE FUNCTION hivemind_app.flush_post_notifications_for_blocks(
    _first_block INT, _last_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
    _min_block INT;
BEGIN
    _min_block := hivemind_app.block_before_irreversible('90 days');

    IF _last_block <= _min_block THEN
        RETURN 0;
    END IF;

    WITH log_account_rep AS (
        SELECT
            account_id,
            LOG(10, ABS(nullif(reputation, 0))) AS rep,
            (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
        FROM reptracker_app.account_reputations
    ),
    calculate_rep AS (
        SELECT account_id, GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
        FROM log_account_rep lar
    ),
    final_rep AS (
        SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep cr
    ),
    -- Find new comments in this block range with depth > 0
    new_comments AS (
        SELECT
            hp.id AS post_id,
            hp.author_id AS src,
            hp_parent.author_id AS dst,
            hp.parent_id AS dst_post_id,
            hp.depth,
            hp.block_num,
            hp.created_at,
            ROW_NUMBER() OVER (PARTITION BY hp.block_num ORDER BY hp.id) AS counter
        FROM hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_posts hp_parent ON hp.parent_id = hp_parent.id
        WHERE hp.block_num_created BETWEEN _first_block AND _last_block
          AND hp.depth > 0
          AND hp.counter_deleted = 0
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
        COALESCE(r.rep, 25),
        '', '', ''
    FROM new_comments nc
    JOIN hivemind_app.hive_accounts ha ON nc.src = ha.id
    LEFT JOIN hivemind_app.muted m ON m.follower = nc.dst AND m.following = nc.src
    LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = nc.dst
    LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = nc.src
    LEFT JOIN final_rep r ON ha.haf_id = r.account_id
    WHERE nc.block_num > _min_block
      AND COALESCE(r.rep, 25) > 0
      AND nc.src IS DISTINCT FROM nc.dst
      AND m.follower IS NULL AND mi.following IS NULL
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
BEGIN
    _min_block := hivemind_app.block_before_irreversible('90 days');

    IF _last_block <= _min_block THEN
        RETURN 0;
    END IF;

    -- Follow notifications use the events staging table populated by process_follows_for_blocks().
    -- This tracks every follow event (including re-follows after unfollows) rather than just
    -- the final state from the follows table.

    WITH log_account_rep AS (
        SELECT
            account_id,
            LOG(10, ABS(nullif(reputation, 0))) AS rep,
            (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
        FROM reptracker_app.account_reputations
    ),
    calculate_rep AS (
        SELECT account_id, GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
        FROM log_account_rep lar
    ),
    final_rep AS (
        SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep cr
    ),
    new_follows AS (
        SELECT
            ha_f.id AS follower,
            ha_g.id AS following,
            fe.block_num,
            hb.created_at,
            ROW_NUMBER() OVER (PARTITION BY fe.block_num ORDER BY fe.op_seq) AS counter
        FROM hivemind_app._follow_notification_events fe
        JOIN hivemind_app.hive_accounts ha_f ON ha_f.name = fe.follower_name
        JOIN hivemind_app.hive_accounts ha_g ON ha_g.name = fe.following_name
        JOIN hivemind_app.blocks_view hb ON hb.num = (fe.block_num - 1)
        WHERE fe.block_num BETWEEN _first_block AND _last_block
    )
    INSERT INTO hivemind_app.hive_notification_cache
    (id, block_num, type_id, created_at, src, dst, dst_post_id, post_id, score, payload, community, community_title)
    SELECT DISTINCT
        hivemind_app.notification_id(nf.created_at, 15, nf.counter::INT),
        nf.block_num, 15, nf.created_at,
        nf.follower, nf.following,
        NULL::INTEGER, NULL::INTEGER,
        COALESCE(rep.rep, 25),
        '', '', ''
    FROM new_follows nf
    LEFT JOIN hivemind_app.muted m ON m.follower = nf.following AND m.following = nf.follower
    LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = nf.following
    LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = nf.follower
    LEFT JOIN hivemind_app.hive_accounts ha ON ha.id = nf.follower
    LEFT JOIN final_rep rep ON ha.haf_id = rep.account_id
    WHERE nf.block_num > _min_block
      AND COALESCE(rep.rep, 25) > 0
      AND nf.follower IS DISTINCT FROM nf.following
      AND m.follower IS NULL AND mi.following IS NULL
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
BEGIN
    _min_block := hivemind_app.block_before_irreversible('90 days');

    IF _last_block <= _min_block THEN
        RETURN 0;
    END IF;

    WITH log_account_rep AS (
        SELECT
            account_id,
            LOG(10, ABS(nullif(reputation, 0))) AS rep,
            (CASE WHEN reputation < 0 THEN -1 ELSE 1 END) AS is_neg
        FROM reptracker_app.account_reputations
    ),
    calculate_rep AS (
        SELECT account_id, GREATEST(lar.rep - 9, 0) * lar.is_neg AS rep
        FROM log_account_rep lar
    ),
    final_rep AS (
        SELECT account_id, (cr.rep * 7.5 + 25)::INT AS rep FROM calculate_rep cr
    ),
    new_reblogs AS (
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
        COALESCE(rep.rep, 25),
        '', '', ''
    FROM new_reblogs nr
    JOIN hivemind_app.hive_accounts ha ON nr.src = ha.id
    LEFT JOIN hivemind_app.muted m ON m.follower = nr.dst AND m.following = nr.src
    LEFT JOIN hivemind_app.follow_muted fm ON fm.follower = nr.dst
    LEFT JOIN hivemind_app.muted mi ON mi.follower = fm.following AND mi.following = nr.src
    LEFT JOIN final_rep rep ON ha.haf_id = rep.account_id
    WHERE nr.block_num > _min_block
      AND COALESCE(rep.rep, 25) > 0
      AND nr.src IS DISTINCT FROM nr.dst
      AND m.follower IS NULL AND mi.following IS NULL
    ORDER BY nr.block_num, nr.created_at, nr.src, nr.dst, nr.dst_post_id, nr.post_id
    ON CONFLICT DO NOTHING;

    GET DIAGNOSTICS _count = ROW_COUNT;
    RETURN _count;
END
$function$ LANGUAGE plpgsql VOLATILE;
