ALTER FUNCTION hive.app_next_block(text) RENAME TO app_next_block_haf;

CREATE OR REPLACE FUNCTION hive.app_next_block(
    _context_name text)
    RETURNS hive.blocks_range
    LANGUAGE 'plpgsql'
AS
$BODY$
DECLARE
    __last_block_for_massive CONSTANT INT = 4999979;
    __first_block_to_process          INT;
    __last_block_to_process           INT;
    __result                          hive.blocks_range;
BEGIN
    SELECT *
    FROM hive.app_next_block_haf(_context_name)
    INTO __first_block_to_process, __last_block_to_process;

    IF __last_block_to_process > __last_block_for_massive THEN
        __last_block_to_process = __last_block_for_massive;
    END IF;

    IF __first_block_to_process > __last_block_for_massive THEN
        __last_block_to_process = __first_block_to_process;
    END IF;


    __result.first_block = __first_block_to_process;
    __result.last_block = __last_block_to_process;
    RETURN __result;
END;
$BODY$;
