DROP TYPE IF EXISTS hivemind_postgrest_utilities.relationship CASCADE;
CREATE TYPE hivemind_postgrest_utilities.relationship AS (
    follows BOOLEAN,
    ignores BOOLEAN,
    blacklists BOOLEAN,
    follows_blacklists BOOLEAN,
    follows_muted BOOLEAN
);

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_relationship_between_accounts;
CREATE FUNCTION hivemind_postgrest_utilities.get_relationship_between_accounts(IN _account1_id INT, IN _account2_id INT)
RETURNS hivemind_postgrest_utilities.relationship
LANGUAGE 'sql'
STABLE
AS
$$
  SELECT
    EXISTS (SELECT 1 FROM hivemind_app.follows WHERE follower=_account1_id  AND FOLLOWING=_account2_id),
    EXISTS (SELECT 1 FROM hivemind_app.muted WHERE follower=_account1_id  AND FOLLOWING=_account2_id),
    EXISTS (SELECT 1 FROM hivemind_app.blacklisted WHERE follower=_account1_id  AND FOLLOWING=_account2_id),
    EXISTS (SELECT 1 FROM hivemind_app.follow_blacklisted WHERE follower=_account1_id  AND FOLLOWING=_account2_id),
    EXISTS (SELECT 1 FROM hivemind_app.follow_muted WHERE follower=_account1_id  AND FOLLOWING=_account2_id);
$$
;
