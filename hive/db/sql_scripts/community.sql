DROP FUNCTION hivemind_app.set_community_role;
CREATE OR REPLACE FUNCTION hivemind_app.set_community_role(
    p_account_id INTEGER,
    p_community_id INTEGER,
    p_role_id INTEGER,
    p_date TIMESTAMP,
    p_max_mod_nb INTEGER,
    p_mod_role_threshold INTEGER
) RETURNS TABLE(status TEXT, mod_count BIGINT) AS $$
BEGIN
    RETURN QUERY
    WITH mod_check AS (
        SELECT 
            CASE 
                WHEN p_role_id >= p_mod_role_threshold THEN
                    (SELECT COUNT(*) 
                     FROM hivemind_app.hive_roles 
                     WHERE community_id = p_community_id 
                     AND role_id >= p_mod_role_threshold
                         AND account_id != p_account_id)
                ELSE 0
            END as current_mod_count
    ),
    insert_attempt AS (
        INSERT INTO hivemind_app.hive_roles (account_id, community_id, role_id, created_at)
        SELECT p_account_id, p_community_id, p_role_id, p_date
        FROM mod_check
        WHERE current_mod_count < p_max_mod_nb OR p_role_id < p_mod_role_threshold
        ON CONFLICT (account_id, community_id) 
        DO UPDATE SET role_id = p_role_id
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