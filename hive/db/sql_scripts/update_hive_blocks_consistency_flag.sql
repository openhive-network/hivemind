DROP FUNCTION IF EXISTS hivemind_app.update_last_imported_block;
CREATE OR REPLACE FUNCTION hivemind_app.update_last_imported_block(
    in _block_number INTEGER)
    RETURNS VOID
    LANGUAGE 'plpgsql'
    VOLATILE
AS
$BODY$
BEGIN
    UPDATE hivemind_app.hive_state
    SET last_imported_block_num = _block_number;
END
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.update_last_completed_block;
CREATE OR REPLACE FUNCTION hivemind_app.update_last_completed_block(
    in _block_number INTEGER)
    RETURNS VOID
    LANGUAGE 'plpgsql'
    VOLATILE
AS
$BODY$
BEGIN
    UPDATE hivemind_app.hive_state
    SET last_completed_block_num = _block_number;
END
$BODY$
;
