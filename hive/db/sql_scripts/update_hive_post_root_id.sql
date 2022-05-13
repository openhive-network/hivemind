DROP FUNCTION IF EXISTS hivemind_app.update_hive_posts_root_id(INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION hivemind_app.update_hive_posts_root_id(in _first_block_num INTEGER, _last_block_num INTEGER)
    RETURNS void
    LANGUAGE 'plpgsql'
    VOLATILE
AS $BODY$
BEGIN

--- _first_block_num can be null together with _last_block_num
UPDATE hivemind_app.hive_posts uhp
SET root_id = id
WHERE uhp.root_id = 0 AND (_first_block_num IS NULL OR (uhp.block_num >= _first_block_num AND uhp.block_num <= _last_block_num))
;
END
$BODY$;
