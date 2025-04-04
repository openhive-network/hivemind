DROP VIEW IF EXISTS hivemind_app.hive_votes_view
;
CREATE OR REPLACE VIEW hivemind_app.hive_votes_view
AS
SELECT
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
    hivemind_app.hive_votes hv
INNER JOIN hivemind_app.hive_accounts_view ha_v ON ha_v.id = hv.voter_id
INNER JOIN hivemind_app.hive_accounts ha_a ON ha_a.id = hv.author_id
INNER JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hv.permlink_id
;
