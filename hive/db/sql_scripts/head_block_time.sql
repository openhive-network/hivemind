DROP FUNCTION IF EXISTS hivemind_app.head_block_time CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.head_block_time()
RETURNS TIMESTAMP
LANGUAGE 'sql' STABLE
AS
$BODY$
SELECT hb.created_at FROM hive.hivemind_app_blocks_view hb ORDER BY hb.num DESC LIMIT 1
$BODY$
;


DROP FUNCTION IF EXISTS hivemind_app.block_before_head CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.block_before_head( in _time INTERVAL )
RETURNS hive.hivemind_app_blocks_view.num%TYPE
LANGUAGE 'sql' STABLE
AS
$BODY$
SELECT MAX(hb1.num) - CAST( extract(epoch from _time)/3 as INTEGER ) FROM hive.hivemind_app_blocks_view hb1
$BODY$
