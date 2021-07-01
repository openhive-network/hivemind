DROP FUNCTION IF EXISTS update_hive_blocks_consistency_flag;

CREATE OR REPLACE FUNCTION update_hive_blocks_consistency_flag(
  in _first_block_num INTEGER,
  in _last_block_num INTEGER)
  RETURNS VOID 
  LANGUAGE 'plpgsql'
  VOLATILE 
AS $BODY$
BEGIN
  UPDATE hive_blocks
  SET completed = true
  WHERE (_first_block_num IS NULL AND _last_block_num IS NULL) OR (num BETWEEN _first_block_num AND _last_block_num);
END
$BODY$
;

