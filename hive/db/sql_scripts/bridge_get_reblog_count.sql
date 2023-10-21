DROP FUNCTION IF EXISTS hivemind_app.get_reblog_count;

CREATE OR REPLACE FUNCTION hivemind_app.get_reblog_count(_post_id hivemind_app.hive_posts.id%TYPE)
RETURNS INTEGER
LANGUAGE 'plpgsql'
AS
$$
BEGIN
    RETURN (SELECT COUNT(*) FROM hivemind_app.hive_reblogs hr WHERE hr.post_id = _post_id);
end;
$$;
