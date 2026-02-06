DROP TYPE IF EXISTS hivemind_app.hive_api_operation CASCADE;
CREATE TYPE hivemind_app.hive_api_operation AS (
    id BIGINT,
    block_num INT,
    operation_type_id SMALLINT,
    is_virtual BOOLEAN,
    body VARCHAR
);

DROP TYPE IF EXISTS hivemind_app.hive_api_operation_in_block CASCADE;
CREATE TYPE hivemind_app.hive_api_operation_in_block AS (
      block_num INT
    , operations jsonb[] -- hivemind_app.hive_api_operation
);


CREATE OR REPLACE FUNCTION hivemind_app.enum_operations4hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hive_api_operation_in_block
AS
$function$
BEGIN
    /** Hivemind requires only following kinds of virtual operations:
    author_reward_operation                 = 51
    comment_reward_operation                = 53
    effective_comment_vote_operation        = 72
    comment_payout_update_operation         = 61
    ineffective_delete_comment_operation    = 73
    */


    RETURN QUERY -- enum_operations4hivemind
        SELECT
            op.block_num
             , ARRAY_AGG( to_jsonb(op.*) ORDER BY op.id )
        FROM
            (SELECT
                    ho.id
                  , ho.block_num
                  , ho.op_type_id as operation_type_id
                  , ho.op_type_id >= 50 AS is_virtual
                  , ho.body::VARCHAR
             FROM hivemind_app.operations_view ho
             WHERE ho.block_num BETWEEN _first_block AND _last_block
               AND (ho.op_type_id < 50
                 OR ho.op_type_id in (51, 53, 61, 72, 73)
                 )
               AND (ho.op_type_id != 18
                 OR ho.body->'value'->>'id' IN ('follow', 'reblog', 'community', 'notify')
                 )
            ) as op
        GROUP BY op.block_num
    ;
END;
$function$
    LANGUAGE plpgsql STABLE
;

DROP TYPE IF EXISTS hivemind_app.hive_api_hivemind_blocks CASCADE;
CREATE TYPE hivemind_app.hive_api_hivemind_blocks AS (
    num INTEGER,
    hash BYTEA,
    prev BYTEA,
    date TEXT,
    operations jsonb[]
);


CREATE OR REPLACE FUNCTION hivemind_app.enum_blocks4hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hive_api_hivemind_blocks
AS
$function$
BEGIN
    RETURN QUERY
        SELECT -- hivemind_app.hive_api_hivemind_blocks
               hb.num
             , hb.hash
             , hb.prev as prev
             , to_char( created_at,  'YYYY-MM-DDThh24:MI:SS' ) as date
             , COALESCE( oper.operations, '{}'::jsonb[] ) as operations
        FROM hivemind_app.blocks_view hb
                 LEFT JOIN (
            SELECT
                   op.block_num
                 , ARRAY_AGG( to_jsonb(op) ORDER BY op.id ) as operations
            FROM
                (SELECT
                     ho.id
                      , ho.block_num
                      , ho.op_type_id as operation_type_id
                      , ho.op_type_id >= 50 AS is_virtual
                      , ho.body::VARCHAR
                 FROM hivemind_app.operations_view ho
                 WHERE ho.block_num BETWEEN _first_block AND _last_block
                   AND (ho.op_type_id < 50
                     OR ho.op_type_id in (51, 53, 61, 72, 73)
                     )
                   AND (ho.op_type_id != 18
                     OR ho.body->'value'->>'id' IN ('follow', 'reblog', 'community', 'notify')
                     )
                ) as op
            GROUP BY op.block_num
        ) as oper ON oper.block_num = hb.num
        WHERE hb.num BETWEEN _first_block AND _last_block
        ORDER by hb.num
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

--- Flat-row functions for massive sync (no ARRAY_AGG, no type wrapper, no hash/prev) ---

DROP TYPE IF EXISTS hivemind_app.hivemind_flat_op CASCADE;
CREATE TYPE hivemind_app.hivemind_flat_op AS (
    block_num INT,
    op_type_id INT,
    body JSONB
);

CREATE OR REPLACE FUNCTION hivemind_app.get_ops_for_hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hivemind_flat_op
AS
$function$
BEGIN
    /** Flat-row query for massive sync - returns only the op types hivemind processes.
        Regular ops:  0=vote, 1=comment, 9=account_create, 10=account_update,
                      14=pow, 17=delete_comment, 18=custom_json, 19=comment_option,
                      23=create_claimed_account, 30=pow2, 41=account_create_with_delegation,
                      43=account_update2
        Virtual ops:  51=author_reward, 53=comment_reward, 61=comment_payout_update,
                      72=effective_comment_vote, 73=ineffective_delete_comment

        Body is returned as jsonb->'value' (the inner payload, no type wrapper).
    */
    RETURN QUERY
        SELECT
            ho.block_num,
            ho.op_type_id,
            ho.body->'value'
        FROM hivemind_app.operations_view ho
        WHERE ho.block_num BETWEEN _first_block AND _last_block
          AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43, 51,53,61,72,73)
          AND (ho.op_type_id != 18
            OR ho.custom_json_type_id IN (
                SELECT id FROM hafd.custom_json_types
                WHERE custom_json_id IN ('follow', 'reblog', 'community', 'notify')
            ))
        ORDER BY ho.id
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

DROP TYPE IF EXISTS hivemind_app.hivemind_block_date CASCADE;
CREATE TYPE hivemind_app.hivemind_block_date AS (
    num INT,
    date TEXT
);

CREATE OR REPLACE FUNCTION hivemind_app.get_block_dates_for_hivemind(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hivemind_block_date
AS
$function$
BEGIN
    RETURN QUERY
        SELECT
            hb.num,
            to_char( hb.created_at, 'YYYY-MM-DDThh24:MI:SS' )
        FROM hivemind_app.blocks_view hb
        WHERE hb.num BETWEEN _first_block AND _last_block
        ORDER BY hb.num
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

--- Extended flat-row function with extracted vote fields ---

DROP TYPE IF EXISTS hivemind_app.hivemind_flat_op_extended CASCADE;
CREATE TYPE hivemind_app.hivemind_flat_op_extended AS (
    block_num INT,
    op_type_id INT,
    body JSONB,
    -- Extracted fields for vote (0) and effective_comment_vote (72) ops.
    -- NULL for all other op types.
    f_voter TEXT,
    f_author TEXT,
    f_permlink TEXT,
    f_weight BIGINT,
    f_rshares BIGINT
);

CREATE OR REPLACE FUNCTION hivemind_app.get_ops_for_hivemind_v2(in _first_block INT, in _last_block INT)
    RETURNS SETOF hivemind_app.hivemind_flat_op_extended
AS
$function$
BEGIN
    /** Like get_ops_for_hivemind but extracts vote fields as separate columns.
        For vote (0) and effective_comment_vote (72) ops, body is NULL and the
        individual fields are populated. For all other ops, body contains the
        inner 'value' payload and the field columns are NULL.

        Uses a CTE so body_binary::jsonb->'value' is computed exactly once per row.
    */
    RETURN QUERY
        WITH op_values AS (
            SELECT ho.id, ho.block_num, ho.op_type_id, ho.body->'value' as val
            FROM hivemind_app.operations_view ho
            WHERE ho.block_num BETWEEN _first_block AND _last_block
              AND ho.op_type_id IN (0,1,9,10,14,17,18,19,23,30,41,43, 51,53,61,72,73)
              AND (ho.op_type_id != 18
                OR ho.custom_json_type_id IN (
                    SELECT id FROM hafd.custom_json_types
                    WHERE custom_json_id IN ('follow', 'reblog', 'community', 'notify')
                ))
        )
        SELECT
            ov.block_num,
            ov.op_type_id,
            CASE WHEN ov.op_type_id NOT IN (0, 72) THEN ov.val END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'voter' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'author' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN ov.val->>'permlink' END,
            CASE WHEN ov.op_type_id IN (0, 72) THEN (ov.val->>'weight')::BIGINT END,
            CASE WHEN ov.op_type_id = 72 THEN (ov.val->>'rshares')::BIGINT END
        FROM op_values ov
        ORDER BY ov.id
    ;
END
$function$
    LANGUAGE plpgsql STABLE
;

