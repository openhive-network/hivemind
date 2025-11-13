DROP FUNCTION IF EXISTS hivemind_app.head_block_time CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.head_block_time()
RETURNS TIMESTAMP
LANGUAGE 'sql' STABLE
AS
$BODY$
    SELECT created_at FROM hivemind_app.blocks_view
    WHERE num = hive.app_get_current_block_num( 'hivemind_app' );
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.block_before_head CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.block_before_head( in _time INTERVAL )
RETURNS hivemind_app.blocks_view.num%TYPE
LANGUAGE 'sql' STABLE
AS
$BODY$
    SELECT hive.app_get_current_block_num( 'hivemind_app' ) - CAST( extract(epoch from _time)/3 as INTEGER );
$BODY$;

DROP FUNCTION IF EXISTS hivemind_app.block_before_irreversible CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.block_before_irreversible( in _time INTERVAL )
RETURNS hivemind_app.blocks_view.num%TYPE
LANGUAGE 'sql' STABLE
AS
$BODY$
    SELECT hive.get_estimated_hive_head_block() - CAST( extract(epoch from _time)/3 as INTEGER );
$BODY$;


DROP FUNCTION IF EXISTS hivemind_app.is_far_than_interval CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.is_far_than_interval( in _time INTERVAL )
    RETURNS boolean
    LANGUAGE 'plpgsql' STABLE
AS
$BODY$
BEGIN
    RETURN hive.app_get_current_block_num( 'hivemind_app' ) <
           hive.get_estimated_hive_head_block() - CAST( extract(epoch from _time)/3 as INTEGER );
END;
$BODY$;