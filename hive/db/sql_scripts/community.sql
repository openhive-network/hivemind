DROP FUNCTION IF EXISTS hivemind_app.set_community_role;
CREATE OR REPLACE FUNCTION hivemind_app.set_community_role(
    _account_id INTEGER,
    _community_id INTEGER,
    _role_id INTEGER,
    _date TIMESTAMP,
    _max_mod_nb INTEGER, -- maximum number of roles >= to mod in a community
    _mod_role_threshold INTEGER -- minimum role id to be counted as
) RETURNS TABLE(status TEXT, mod_count BIGINT) AS $$
BEGIN
    RETURN QUERY
    WITH mod_check AS (
        SELECT 
            CASE 
                WHEN _role_id >= _mod_role_threshold THEN
                    (SELECT COUNT(*) 
                     FROM hivemind_app.hive_roles 
                     WHERE community_id = _community_id
                     AND role_id >= _mod_role_threshold
                         AND account_id != _account_id)
                ELSE 0
            END as current_mod_count
    ),
    insert_attempt AS (
        INSERT INTO hivemind_app.hive_roles (account_id, community_id, role_id, created_at)
        SELECT _account_id, _community_id, _role_id, _date
        FROM mod_check
        WHERE current_mod_count < _max_mod_nb OR _role_id < _mod_role_threshold
        ON CONFLICT (account_id, community_id) 
        DO UPDATE SET role_id = _role_id
        RETURNING *
    )
    SELECT 
        CASE 
            WHEN EXISTS (SELECT 1 FROM insert_attempt) THEN 'success'
            ELSE 'failed_mod_limit'
        END as status,
        (SELECT current_mod_count FROM mod_check) as mod_count;
END;
$$ LANGUAGE plpgsql;