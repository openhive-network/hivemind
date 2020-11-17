DROP VIEW IF EXISTS muted_accounts_by_id_view CASCASE;
CREATE OR REPLACE VIEW muted_accounts_by_id_view AS
SELECT observer_accounts.id AS observer_id,
    following_accounts.id AS muted_id
   FROM ((hive_follows
     JOIN hive_accounts following_accounts ON ((hive_follows.following = following_accounts.id)))
     JOIN hive_accounts observer_accounts ON ((hive_follows.follower = observer_accounts.id)))
  WHERE (hive_follows.state = 2)
UNION
 SELECT observer_accounts.id AS observer_id,
    following_accounts.id AS muted_id
   FROM (((hive_follows hive_follows_direct
     JOIN hive_follows hive_follows_indirect ON ((hive_follows_direct.following = hive_follows_indirect.follower)))
     JOIN hive_accounts following_accounts ON ((hive_follows_indirect.following = following_accounts.id)))
     JOIN hive_accounts observer_accounts ON ((hive_follows_direct.follower = observer_accounts.id)))
  WHERE (hive_follows_direct.follow_muted AND (hive_follows_indirect.state = 2));