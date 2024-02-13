DROP VIEW IF EXISTS hivemind_app.blacklisted_by_observer_view;
CREATE OR REPLACE VIEW hivemind_app.blacklisted_by_observer_view AS
 SELECT  hive_follows.follower AS observer_id,
    following_accounts.id AS blacklisted_id,
    following_accounts.name AS blacklisted_name,
    'my blacklist'::text AS source
   FROM hivemind_app.hive_follows
     JOIN hivemind_app.hive_accounts following_accounts ON hive_follows.following = following_accounts.id
  WHERE hive_follows.blacklisted
UNION ALL
 SELECT hive_follows_direct.follower AS observer_id,
    following_accounts.id AS blacklisted_id,
    following_accounts.name AS blacklisted_name,
    string_agg('blacklisted by '::text || indirect_accounts.name::text, ','::text ORDER BY indirect_accounts.name) AS source
   FROM hivemind_app.hive_follows hive_follows_direct
     JOIN hivemind_app.hive_follows hive_follows_indirect ON hive_follows_direct.following = hive_follows_indirect.follower
     JOIN hivemind_app.hive_accounts following_accounts ON hive_follows_indirect.following = following_accounts.id
     JOIN hivemind_app.hive_accounts indirect_accounts ON hive_follows_indirect.follower = indirect_accounts.id
  WHERE hive_follows_direct.follow_blacklists AND hive_follows_indirect.blacklisted
  GROUP BY hive_follows_direct.follower, following_accounts.id;
