CREATE SCHEMA IF NOT EXISTS hivemind_app;

DROP TYPE IF EXISTS hivemind_app.hive_api_operation CASCADE;
CREATE TYPE hivemind_app.hive_api_operation AS (
    id BIGINT,
    block_num INT,
    operation_type_id SMALLINT,
    is_virtual BOOLEAN,
    body VARCHAR
);

CREATE OR REPLACE FUNCTION hivemind_app.enum_operations4hivemind(in _first_block INT, in _last_block INT)
RETURNS SETOF hivemind_app.hive_api_operation
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
    SELECT ho.id, ho.block_num, ho.op_type_id, ho.op_type_id >= 50 AS is_virtual, ho.body::VARCHAR
    FROM hive.hivemind_app_operations_view ho
    WHERE ho.block_num BETWEEN _first_block AND _last_block
          AND (ho.op_type_id < 50
               OR ho.op_type_id in (51, 53, 61, 72, 73)
              )
    ORDER BY ho.id
;

END
$function$
LANGUAGE plpgsql STABLE
;

DROP TYPE IF EXISTS hivemind_app.hive_api_hivemind_blocks CASCADE;
CREATE TYPE hivemind_app.hive_api_hivemind_blocks AS (
    num INTEGER,
    hash BYTEA,
    prev BYTEA,
    date TEXT,
    tx_number BIGINT,
    op_number BIGINT
    );


CREATE OR REPLACE FUNCTION hivemind_app.enum_blocks4hivemind(in _first_block INT, in _last_block INT)
RETURNS SETOF hivemind_app.hive_api_hivemind_blocks
AS
$function$
BEGIN
RETURN QUERY
SELECT -- hive_api_hivemind_blocks
    hb.num
     , hb.hash
     , hb.prev as prev
     , to_char( created_at,  'YYYY-MM-DDThh24:MI:SS' ) as date
FROM hive.blocks hb
WHERE hb.num BETWEEN _first_block AND _last_block
ORDER by hb.num
;
END
$function$
LANGUAGE plpgsql STABLE
;
