DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_notify_type_from_id;
CREATE FUNCTION hivemind_postgrest_utilities.get_notify_type_from_id(notify_type_id INT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    notify_type TEXT;
BEGIN
    notify_type := CASE notify_type_id
        WHEN 1 THEN 'new_community'
        WHEN 2 THEN 'set_role'
        WHEN 3 THEN 'set_props'
        WHEN 4 THEN 'set_title'
        WHEN 5 THEN 'mute_post'
        WHEN 6 THEN 'unmute_post'
        WHEN 7 THEN 'pin_post'
        WHEN 8 THEN 'unpin_post'
        WHEN 9 THEN 'flag_post'
        WHEN 10 THEN 'error'
        WHEN 11 THEN 'subscribe'
        WHEN 12 THEN 'reply'
        WHEN 13 THEN 'reply_comment'
        WHEN 14 THEN 'reblog'
        WHEN 15 THEN 'follow'
        WHEN 16 THEN 'mention'
        WHEN 17 THEN 'vote'
        ELSE NULL
    END;

	IF notify_type IS NULL THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.invalid_notify_type_id_exception('The provided type_id does not correspond to any known notification type.');
    END IF;

    RETURN notify_type;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_notify_message;
CREATE FUNCTION hivemind_postgrest_utilities.get_notify_message(_row RECORD)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    _msg TEXT;
    _notify_type TEXT;
BEGIN
    _notify_type := hivemind_postgrest_utilities.get_notify_type_from_id(_row.type_id);

    _msg := CASE
        WHEN _notify_type = 'new_community' THEN '<dst> was created'
        WHEN _notify_type = 'set_role' THEN '<src> set your role to <payload>'
        WHEN _notify_type = 'set_props' THEN '<src> set properties <payload>'
        WHEN _notify_type = 'set_title' THEN '<src> set your title to <payload>'
        WHEN _notify_type = 'mute_post' THEN '<src> muted <post> - <payload>'
        WHEN _notify_type = 'unmute_post' THEN '<src> unmuted <post> - <payload>'
        WHEN _notify_type = 'pin_post' THEN '<src> pinned <post>'
        WHEN _notify_type = 'unpin_post' THEN '<src> unpinned <post>'
        WHEN _notify_type = 'flag_post' THEN '<src> flagged <post> - <payload>'
        WHEN _notify_type = 'subscribe' THEN '<src> subscribed to <comm>'
        WHEN _notify_type = 'error' THEN 'error: <payload>'
        WHEN _notify_type = 'reblog' THEN '<src> reblogged your post'
        WHEN _notify_type = 'follow' THEN '<src> followed you'
        WHEN _notify_type = 'reply' THEN '<src> replied to your post'
        WHEN _notify_type = 'reply_comment' THEN '<src> replied to your comment'
        WHEN _notify_type = 'mention' THEN '<src> mentioned you and <other_mentions> others'
        WHEN _notify_type = 'vote' THEN '<src> voted on your post'
    END;

    IF _row.type_id = 17 AND _row.payload IS NOT NULL AND _row.payload <> '' THEN
        _msg := _msg || ' <payload>';
    END IF;

    IF position('<dst>' IN _msg) > 0 THEN
        _msg := replace(_msg, '<dst>', '@' || coalesce(_row.dst, ''));
    END IF;

    IF position('<src>' IN _msg) > 0 THEN
        _msg := replace(_msg, '<src>', '@' || coalesce(_row.src, ''));
    END IF;

    IF position('<post>' IN _msg) > 0 THEN
        _msg := replace(_msg, '<post>', coalesce(_row.post, ''));
    END IF;

    IF position('<payload>' IN _msg) > 0 THEN
        _msg := replace(_msg, '<payload>', coalesce(_row.payload, 'null'));
    END IF;

    IF position('<comm>' IN _msg) > 0 THEN
        _msg := replace(_msg, '<comm>', coalesce(_row.community_title, ''));
    END IF;

    IF position('<other_mentions>' IN _msg) > 0 THEN
        _msg := replace(_msg, '<other_mentions>', (coalesce(_row.number_of_mentions, 1) - 1)::TEXT);
    END IF;

    RETURN _msg;
END;
$$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_number_of_mentions_in_post;
CREATE FUNCTION hivemind_postgrest_utilities.get_number_of_mentions_in_post( _post_id hivemind_app.hive_posts.id%TYPE )
RETURNS INTEGER
LANGUAGE 'plpgsql'
STABLE
AS
$BODY$
BEGIN
  RETURN (
    SELECT COUNT(*) FROM hivemind_app.hive_mentions hm WHERE hm.post_id = _post_id
  );
END
$BODY$;