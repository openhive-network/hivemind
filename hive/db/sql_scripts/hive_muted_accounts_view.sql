 DROP VIEW IF EXISTS hivemind_app.muted_accounts_view;
 CREATE OR REPLACE VIEW hivemind_app.muted_accounts_view AS
 (
   SELECT observer_accounts.name AS observer, following_accounts.name AS muted
   FROM hivemind_app.hive_follows JOIN hivemind_app.hive_accounts following_accounts ON hivemind_app.hive_follows.following = following_accounts.id
                     JOIN hivemind_app.hive_accounts observer_accounts ON hivemind_app.hive_follows.follower = observer_accounts.id
   WHERE hivemind_app.hive_follows.state = 2

   UNION

   SELECT observer_accounts.name AS observer, following_accounts.name AS muted
   FROM hivemind_app.hive_follows hive_follows_direct JOIN hivemind_app.hive_follows hive_follows_indirect ON hive_follows_direct.following = hive_follows_indirect.follower
                                         JOIN hivemind_app.hive_accounts following_accounts ON hive_follows_indirect.following = following_accounts.id
                                         JOIN hivemind_app.hive_accounts observer_accounts ON hive_follows_direct.follower = observer_accounts.id
   WHERE hive_follows_direct.follow_muted AND hive_follows_indirect.state = 2
 );
 