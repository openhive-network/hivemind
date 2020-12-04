DROP VIEW IF EXISTS blacklisted_by_observer_view;
CREATE OR REPLACE VIEW blacklisted_by_observer_view AS
SELECT observer_accounts.id AS observer_id,
    following_accounts.id AS blacklisted_id,
    following_accounts.name AS blacklisted_name,
    'my blacklist'::text AS source
   FROM ((hive_follows
     JOIN hive_accounts following_accounts ON ((hive_follows.following = following_accounts.id)))
     JOIN hive_accounts observer_accounts ON ((hive_follows.follower = observer_accounts.id)))
  WHERE hive_follows.blacklisted
UNION ALL
 SELECT observer_accounts.id AS observer_id,
    following_accounts.id AS blacklisted_id,
    following_accounts.name AS blacklisted_name,
    string_agg(('blacklisted by '::text || (indirect_accounts.name)::text), ','::text ORDER BY indirect_accounts.name) AS source
   FROM (((hive_follows hive_follows_direct
     JOIN hive_follows hive_follows_indirect ON ((hive_follows_direct.following = hive_follows_indirect.follower)))
     JOIN hive_accounts following_accounts ON ((hive_follows_indirect.following = following_accounts.id)))
     JOIN hive_accounts observer_accounts ON ((hive_follows_direct.follower = observer_accounts.id)))
     JOIN hive_accounts indirect_accounts ON ((hive_follows_indirect.follower = indirect_accounts.id))
  WHERE (hive_follows_direct.follow_blacklists AND hive_follows_indirect.blacklisted)
  GROUP BY observer_accounts.id, following_accounts.id;