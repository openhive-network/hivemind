DROP FUNCTION IF EXISTS hivemind_endpoints.hive_api_get_info;
CREATE FUNCTION hivemind_endpoints.hive_api_get_info(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _database_head_block hive.blocks_view.num%TYPE;
    _patch_level_data RECORD;
    _hivemind_data RECORD;
BEGIN
    SELECT num INTO _database_head_block FROM hivemind_app.get_head_state();

    SELECT level, patch_date, patched_to_revision
    INTO _patch_level_data
    FROM hivemind_app.hive_db_patch_level
    ORDER BY level DESC
    LIMIT 1;

    SELECT hivemind_version, hivemind_git_rev, hivemind_git_date
    INTO _hivemind_data
    FROM hivemind_app.hive_state
    LIMIT 1;

    RETURN jsonb_build_object(
        'hivemind_version', _hivemind_data.hivemind_version,
        'hivemind_git_rev', _hivemind_data.hivemind_git_rev,
        'hivemind_git_date', _hivemind_data.hivemind_git_date,
        'database_head_block', _database_head_block,
        'database_patch_date', _patch_level_data.patch_date::TEXT,
        'database_patched_to_revision', _patch_level_data.patched_to_revision,
        'database_schema_version', _patch_level_data.level
    );
END;
$$
;