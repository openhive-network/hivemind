DROP FUNCTION IF EXISTS hivemind_endpoints.hive_api_db_head_state;
CREATE FUNCTION hivemind_endpoints.hive_api_db_head_state(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _head_state RECORD;
BEGIN
    SELECT * INTO _head_state FROM hivemind_app.get_head_state();

    RETURN jsonb_build_object(
        'db_head_block', _head_state.num,
        'db_head_time', _head_state.created_at::TEXT,
        'db_head_age', EXTRACT(EPOCH FROM NOW()) - _head_state.age::FLOAT
    );
END;
$$
;