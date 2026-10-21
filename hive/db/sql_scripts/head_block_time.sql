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

-- Blocks at or before the result are older than _time at the head the sync ends at: notifications
-- are built only for blocks after block_before_irreversible('90 days'), and payouts of posts at or
-- before block_before_irreversible('7 days') are assumed done when the massive sync ends.
-- While HAF still replays (the context opted in to early block processing), the irreversible block
-- trails the chain head by up to years, so the irreversible-relative estimate would keep every
-- block. The sync cannot end before reaching the chain head of now(), so when the irreversible
-- block is older than now() - _time, every block up to it is old enough.
DROP FUNCTION IF EXISTS hivemind_app.block_before_irreversible CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.block_before_irreversible( in _time INTERVAL )
RETURNS hivemind_app.blocks_view.num%TYPE
LANGUAGE 'plpgsql' STABLE
AS
$BODY$
DECLARE
    __irreversible hivemind_app.blocks_view.num%TYPE := hive.app_get_irreversible_block( 'hivemind_app' );
BEGIN
    IF NOT hive.is_instance_ready()
       AND ( SELECT hb.created_at FROM hafd.blocks hb WHERE hb.num = __irreversible ) <= ( now() AT TIME ZONE 'UTC' ) - _time
    THEN
        RETURN __irreversible;
    END IF;
    RETURN __irreversible - CAST( extract(epoch from _time)/3 as INTEGER );
END
$BODY$;
