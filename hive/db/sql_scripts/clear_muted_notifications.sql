DROP FUNCTION IF EXISTS hivemind_app.clear_muted_notifications;
CREATE OR REPLACE PROCEDURE hivemind_app.clear_muted_notifications()
    LANGUAGE sql
AS
$BODY$
  DELETE FROM hivemind_app.hive_notification_cache AS n
  WHERE EXISTS (
    SELECT NULL FROM hivemind_app.muted AS m
    WHERE n.src=m.following AND n.dst=m.follower
  );
$BODY$;
