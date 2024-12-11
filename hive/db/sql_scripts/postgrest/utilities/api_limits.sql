-- sets the maximum number of posts an api user can ask for at a given time
-- used in functions like (bridge|condenser_api).get_account_posts
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_max_posts_per_call_limit;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_max_posts_per_call_limit() RETURNS INTEGER AS $$
BEGIN
    RETURN COALESCE(NULLIF(current_setting('hivemind_app.max_posts_per_call', true), '')::INTEGER, 20);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
