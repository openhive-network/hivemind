DROP FUNCTION IF EXISTS hivemind_app.head_block_time CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.head_block_time()
RETURNS TIMESTAMP
LANGUAGE 'sql' STABLE
AS
$BODY$
SELECT last_imported_block_date FROM hivemind_app.hive_state LIMIT 1
$BODY$
;


DROP FUNCTION IF EXISTS hivemind_app.block_before_head CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.block_before_head( in _time INTERVAL )
RETURNS hivemind_app.blocks_view.num%TYPE
LANGUAGE 'sql' STABLE
AS
$BODY$
SELECT last_imported_block_num - CAST( extract(epoch from _time)/3 as INTEGER ) FROM hivemind_app.hive_state LIMIT 1
$BODY$
