DROP FUNCTION IF EXISTS head_block_time;
CREATE OR REPLACE FUNCTION head_block_time()
RETURNS TIMESTAMP
LANGUAGE 'sql' STABLE
AS
$BODY$
SELECT hb.created_at FROM hive_blocks hb ORDER BY hb.num DESC LIMIT 1
$BODY$
;


DROP FUNCTION IF EXISTS block_before_head;
CREATE OR REPLACE FUNCTION block_before_head( in _time  INTERVAL )
RETURNS hive_blocks.num%TYPE
LANGUAGE 'sql' STABLE
AS
$BODY$
SELECT MAX(hb1.num) - CAST( extract(epoch from _time)/3 as INTEGER ) FROM hive_blocks hb1
$BODY$
