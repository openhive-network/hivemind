DROP VIEW IF EXISTS hive_votes_view
;
CREATE OR REPLACE VIEW hive_votes_view
AS
SELECT
    hv.id,
    hv.voter_id as voter_id,
    ha_a.name as author,
    hpd.permlink as permlink,
    vote_percent as percent,
    ha_v.reputation as reputation,
    rshares,
    last_update,
    ha_v.name as voter,
    weight,
    num_changes,
    hv.permlink_id as permlink_id,
    post_id,
    is_effective
FROM
    hive_votes hv
INNER JOIN hive_accounts ha_v ON ha_v.id = hv.voter_id
INNER JOIN hive_accounts ha_a ON ha_a.id = hv.author_id
INNER JOIN hive_permlink_data hpd ON hpd.id = hv.permlink_id
;
