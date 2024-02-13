DROP VIEW IF EXISTS hivemind_app.muted_accounts_by_id_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.muted_accounts_by_id_view AS
 SELECT hive_follows.follower AS observer_id,
    hive_follows.following AS muted_id
   FROM hivemind_app.hive_follows
  WHERE hive_follows.state = 2
UNION
 SELECT hive_follows_direct.follower AS observer_id,
    hive_follows_indirect.following AS muted_id
   FROM hivemind_app.hive_follows hive_follows_direct
     JOIN hivemind_app.hive_follows hive_follows_indirect ON hive_follows_direct.following = hive_follows_indirect.follower
  WHERE hive_follows_direct.follow_muted AND hive_follows_indirect.state = 2;
