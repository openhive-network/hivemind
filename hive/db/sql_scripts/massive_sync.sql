--- Pure SQL Massive Sync Functions for Hivemind ---
--- Replaces the Python dispatch loop with SQL functions that read from a staging table ---

-- ============================================================================
-- 1. Staging Table DDL
-- ============================================================================

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


-- ============================================================================
-- 2. load_ops_staging(_first_block, _last_block)
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.load_ops_staging(
    _first_block INT,
    _last_block INT
) RETURNS VOID AS $function$
BEGIN
    TRUNCATE hivemind_app._ops_staging;

    INSERT INTO hivemind_app._ops_staging (id, block_num, block_date, op_type_id, val)
    SELECT ho.id, ho.block_num, hb.created_at, ho.op_type_id, ho.body->'value'
    FROM hivemind_app.operations_view ho
    JOIN hivemind_app.blocks_view hb ON hb.num = ho.block_num
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
        SELECT DISTINCT acct_name, first_block_date, first_block_num,
               -- Get metadata from the first occurrence (for types that carry it)
               first_value(posting_json_metadata) OVER (
                   PARTITION BY acct_name ORDER BY id
               ) AS posting_json_metadata,
               first_value(json_metadata) OVER (
                   PARTITION BY acct_name ORDER BY id
               ) AS json_metadata
        FROM (
            SELECT
                s.id,
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
    ),
    -- Only insert accounts that don't already exist
    to_insert AS (
        SELECT na.acct_name, na.first_block_date, na.first_block_num,
               na.posting_json_metadata, na.json_metadata
        FROM (
            SELECT DISTINCT ON (acct_name) acct_name, first_block_date, first_block_num,
                   posting_json_metadata, json_metadata
            FROM new_accounts
        ) na
        WHERE NOT EXISTS (
            SELECT 1 FROM hivemind_app.hive_accounts ha WHERE ha.name = na.acct_name
        )
    ),
    inserted AS (
        INSERT INTO hivemind_app.hive_accounts (name, created_at, posting_json_metadata, json_metadata, haf_id)
        SELECT ti.acct_name, ti.first_block_date, ti.posting_json_metadata, ti.json_metadata,
               (SELECT av.id FROM hivemind_app.accounts_view av WHERE av.name = ti.acct_name)
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
BEGIN
    -- Community registration happens when an account name matches hive-XXXXX pattern
    -- and the block is after community_support_start_block.
    -- The existing community.sql handles this via community_check_account_name().
    -- We call it for each newly created account that matches the pattern.
    NULL; -- Placeholder: community registration is handled in process_community_from_staging
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
            count(*) OVER (PARTITION BY voter, author, permlink) AS num_changes
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
            (ro.val->>'json')::jsonb AS inner_json
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

    -- Process deletes
    PERFORM hivemind_app.delete_reblog_feed_cache(
        ro.author::VARCHAR, ro.permlink::VARCHAR, ro.account::VARCHAR
    )
    FROM _reblog_ops ro
    WHERE ro.is_delete;

    -- Process creates: deduplicate per (author, permlink, account), last action wins
    WITH deduped AS (
        SELECT DISTINCT ON (author, permlink, account)
            account, author, permlink, block_date, block_num
        FROM _reblog_ops
        WHERE NOT is_delete
        ORDER BY author, permlink, account, id DESC
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
            (s.val->>'json')::jsonb AS inner_json
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
            val->>'total_payout_value' AS total_payout_value,
            val->>'curator_payout_value' AS curator_payout_value,
            val->>'beneficiary_payout_value' AS beneficiary_payout_value,
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
CREATE OR REPLACE FUNCTION hivemind_app.legacy_amount(_amount TEXT)
RETURNS TEXT AS $function$
BEGIN
    -- Pass-through: already in the correct format for hive_posts columns
    RETURN _amount;
END
$function$ LANGUAGE plpgsql IMMUTABLE;

-- Helper: extract numeric value from HBD amount string
CREATE OR REPLACE FUNCTION hivemind_app.sbd_amount(_amount TEXT)
RETURNS DECIMAL AS $function$
BEGIN
    IF _amount IS NULL THEN RETURN 0; END IF;
    RETURN split_part(_amount, ' ', 1)::DECIMAL;
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
    RETURN _raw::DECIMAL / power(10, _precision);
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
    -- Step 1: Collect ineffective delete keys (type 73)
    SELECT array_agg((s.val->>'author') || '/' || (s.val->>'permlink'))
    INTO _ineffective_keys
    FROM hivemind_app._ops_staging s
    WHERE s.op_type_id = 73;
    _ineffective_keys := COALESCE(_ineffective_keys, '{}');

    -- Step 2: Collect all comment ops (type 1) with their original staging ID for ordering
    CREATE TEMP TABLE _comment_staging ON COMMIT DROP AS
    SELECT
        s.id AS staging_id,
        s.block_num,
        s.block_date,
        s.val->>'author' AS author,
        s.val->>'permlink' AS permlink,
        s.val->>'parent_author' AS parent_author,
        s.val->>'parent_permlink' AS parent_permlink,
        s.val AS op_body
    FROM hivemind_app._ops_staging s
    WHERE s.op_type_id = 1
    ORDER BY s.id;

    -- Results accumulator (used across waves)
    CREATE TEMP TABLE _post_results (
        seq_id INT, post_id INT, is_new_post BOOLEAN,
        author_id INT, permlink_id INT, depth SMALLINT,
        parent_id INT, parent_author_id INT,
        community_id INT, is_post_muted BOOLEAN, muted_reasons INT,
        block_num INT, block_date TIMESTAMP, op_body JSONB
    ) ON COMMIT DROP;

    -- Normalize parent_author/parent_permlink for edits (first occurrence determines parent)
    UPDATE _comment_staging cs
    SET parent_author = first_parent.parent_author,
        parent_permlink = first_parent.parent_permlink
    FROM (
        SELECT DISTINCT ON (author, permlink)
            author, permlink, parent_author, parent_permlink
        FROM _comment_staging
        ORDER BY author, permlink, staging_id
    ) first_parent
    WHERE cs.author = first_parent.author
      AND cs.permlink = first_parent.permlink
      AND (cs.parent_author IS DISTINCT FROM first_parent.parent_author
           OR cs.parent_permlink IS DISTINCT FROM first_parent.parent_permlink);

    -- Step 3: Bulk-insert permlinks and categories
    INSERT INTO hivemind_app.hive_permlink_data (permlink)
    SELECT DISTINCT p FROM (
        SELECT permlink AS p FROM _comment_staging
        UNION
        SELECT parent_permlink AS p FROM _comment_staging WHERE parent_author != ''
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO hivemind_app.hive_category_data (category)
    SELECT DISTINCT parent_permlink
    FROM _comment_staging
    WHERE parent_author IS NULL OR parent_author = ''
    ON CONFLICT (category) DO NOTHING;

    -- Step 4: Process root posts via batch function (single call with all root ops)
    INSERT INTO _post_results
    SELECT br.seq_id, br.id, br.is_new_post, br.author_id, br.permlink_id,
           br.depth, br.parent_id, br.parent_author_id, br.community_id,
           br.is_post_muted, br.muted_reasons, cs.block_num, cs.block_date, cs.op_body
    FROM hivemind_app.process_root_posts_batch(
        ARRAY(
            SELECT ROW(cs.staging_id, cs.author, cs.permlink,
                       ''::VARCHAR, cs.parent_permlink,
                       cs.block_date, _community_support_start_block,
                       cs.block_num, ARRAY[]::VARCHAR[])::hivemind_app.hive_post_op_input
            FROM _comment_staging cs
            WHERE cs.parent_author IS NULL OR cs.parent_author = ''
            ORDER BY cs.staging_id
        )
    ) br
    JOIN _comment_staging cs ON cs.staging_id = br.seq_id;

    -- Step 5: Process comments with wave-based resolution
    FOR _wave IN 1..20 LOOP
        -- Count unprocessed comments (not yet in results)
        SELECT count(*) INTO _remaining
        FROM _comment_staging cs
        WHERE cs.parent_author IS NOT NULL AND cs.parent_author != ''
          AND NOT EXISTS (SELECT 1 FROM _post_results pr WHERE pr.seq_id = cs.staging_id);

        EXIT WHEN _remaining = 0;

        -- Process batch: pass all unprocessed comments, function returns only those
        -- whose parent is now resolvable (exists in hive_posts)
        INSERT INTO _post_results
        SELECT br.seq_id, br.id, br.is_new_post, br.author_id, br.permlink_id,
               br.depth, br.parent_id, br.parent_author_id, br.community_id,
               br.is_post_muted, br.muted_reasons, cs.block_num, cs.block_date, cs.op_body
        FROM hivemind_app.process_comments_batch(
            ARRAY(
                SELECT ROW(cs.staging_id, cs.author, cs.permlink,
                           cs.parent_author, cs.parent_permlink,
                           cs.block_date, _community_support_start_block,
                           cs.block_num, ARRAY[]::VARCHAR[])::hivemind_app.hive_post_op_input
                FROM _comment_staging cs
                WHERE cs.parent_author IS NOT NULL AND cs.parent_author != ''
                  AND NOT EXISTS (SELECT 1 FROM _post_results pr WHERE pr.seq_id = cs.staging_id)
                ORDER BY cs.staging_id
            )
        ) br
        JOIN _comment_staging cs ON cs.staging_id = br.seq_id;

        GET DIAGNOSTICS _processed_count = ROW_COUNT;
        EXIT WHEN _processed_count = 0;
    END LOOP;

    -- Step 6: Process comment_options (type 19) - update hive_posts columns
    WITH co_ops AS (
        SELECT
            s.id,
            s.val->>'author' AS author,
            s.val->>'permlink' AS permlink,
            COALESCE(s.val->>'max_accepted_payout', '1000000.000 HBD') AS max_accepted_payout,
            COALESCE((s.val->>'percent_hbd')::INT, 10000) AS percent_hbd,
            COALESCE((s.val->>'allow_votes')::BOOLEAN, TRUE) AS allow_votes,
            COALESCE((s.val->>'allow_curation_rewards')::BOOLEAN, TRUE) AS allow_curation_rewards,
            COALESCE(
                (SELECT jsonb_agg(elem->'value'->'beneficiaries')
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

    -- Return all post results
    RETURN QUERY SELECT * FROM _post_results ORDER BY seq_id;

    DROP TABLE IF EXISTS _post_results;
    DROP TABLE IF EXISTS _comment_staging;
END
$function$ LANGUAGE plpgsql VOLATILE;


-- ============================================================================
-- 10. process_community_from_staging()
-- ============================================================================

CREATE OR REPLACE FUNCTION hivemind_app.process_community_from_staging(
    _community_support_start_block INT
) RETURNS INT AS $function$
DECLARE
    _count INT := 0;
    _rec RECORD;
    _val JSONB;
    _inner_json JSONB;
    _auth_account TEXT;
    _data JSONB;
    _action TEXT;
BEGIN
    -- Process community custom_json ops from staging (type 18, custom_json_id = 'community')
    -- Each action type dispatches to an existing SQL function

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

        -- Dispatch to existing community SQL functions via the Python-equivalent process
        -- This delegates to the existing community.sql functions
        BEGIN
            PERFORM hivemind_app.process_community_op(
                _auth_account, _action, _data, _rec.block_date, _rec.block_num
            );
            _count := _count + 1;
        EXCEPTION WHEN OTHERS THEN
            -- Community op failures are non-fatal (matching Python behavior)
            NULL;
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
        hivemind_app.notification_id(hn.last_update, 17, hn.counter) AS id,
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
                hp.payout + hp.pending_payout, hp.rshares, hv.rshares
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

    -- Follow notifications are generated by process_follows_for_blocks() which returns
    -- notification data. In the SQL-only path, follows are processed inline and
    -- notifications are inserted here based on the follows table changes.
    -- Since follows are already committed by Phase 4, we can query the follows table
    -- for new follows in this block range.

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
            f.follower,
            f.following,
            f.block_num,
            hb.created_at,
            ROW_NUMBER() OVER (PARTITION BY f.block_num ORDER BY f.follower, f.following) AS counter
        FROM hivemind_app.follows f
        JOIN hivemind_app.blocks_view hb ON hb.num = (f.block_num - 1)
        WHERE f.block_num BETWEEN _first_block AND _last_block
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
