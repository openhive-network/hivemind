DROP TYPE IF EXISTS hivemind_app.hive_api_operation CASCADE;
CREATE TYPE hivemind_app.hive_api_operation AS (
    id BIGINT,
    block_num INT,
    operation_type_id INTEGER,
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
             , oper.operations as operations
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

