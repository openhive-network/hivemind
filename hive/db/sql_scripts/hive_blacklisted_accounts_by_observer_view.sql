DROP VIEW IF EXISTS hivemind_app.blacklisted_by_observer_view;
CREATE OR REPLACE VIEW hivemind_app.blacklisted_by_observer_view AS
  SELECT hive_follows.follower AS observer_id,
    hive_follows.following AS blacklisted_id,
    'my blacklist'::text AS source
   FROM hivemind_app.hive_follows
  WHERE hive_follows.blacklisted
UNION ALL
 SELECT hive_follows_direct.follower AS observer_id,
    hive_follows_indirect.following AS blacklisted_id,
    string_agg('blacklisted by '::text || indirect_accounts.name::text, ','::text ORDER BY indirect_accounts.name) AS source
   FROM hivemind_app.hive_follows hive_follows_direct
     JOIN hivemind_app.hive_follows hive_follows_indirect ON hive_follows_direct.following = hive_follows_indirect.follower
     JOIN hivemind_app.hive_accounts indirect_accounts ON hive_follows_indirect.follower = indirect_accounts.id
  WHERE hive_follows_direct.follow_blacklists AND hive_follows_indirect.blacklisted
  GROUP BY hive_follows_direct.follower, hive_follows_indirect.following
  ;
