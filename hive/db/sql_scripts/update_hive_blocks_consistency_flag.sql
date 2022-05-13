DROP FUNCTION IF EXISTS hivemind_app.update_hive_blocks_consistency_flag;

CREATE OR REPLACE FUNCTION hivemind_app.update_hive_blocks_consistency_flag(
  in _first_block_num INTEGER,
  in _last_block_num INTEGER)
  RETURNS VOID 
  LANGUAGE 'plpgsql'
  VOLATILE 
AS $BODY$
BEGIN

  IF _first_block_num IS NULL OR _last_block_num IS NULL THEN
    RAISE EXCEPTION 'First/last block number is required' USING ERRCODE = 'CEHMA';
  END IF;

  UPDATE hivemind_app.hive_blocks
  SET completed = True
  WHERE num BETWEEN _first_block_num AND _last_block_num;
END
$BODY$
;

