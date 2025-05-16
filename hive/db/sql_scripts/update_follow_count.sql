DROP FUNCTION IF EXISTS hivemind_app.update_follow_count;
CREATE OR REPLACE FUNCTION hivemind_app.update_follow_count(
  in _account_names TEXT[]
)
RETURNS VOID
LANGUAGE 'plpgsql'
AS
$BODY$
BEGIN
UPDATE hivemind_app.hive_accounts ha
SET
  followers = data_set.followers_count,
  following = data_set.following_count
FROM
  (
    WITH target_accounts AS (
      SELECT id, name
      FROM hivemind_app.hive_accounts
      WHERE name = ANY(_account_names)
    )
    SELECT
        ta.id AS user_id,
        (SELECT COUNT(1) FROM hivemind_app.follows AS hf1 WHERE hf1.following = ta.id) AS followers_count,
        (SELECT COUNT(1) FROM hivemind_app.follows AS hf2 WHERE hf2.follower = ta.id) AS following_count
    FROM
        target_accounts AS ta
  ) AS data_set(user_id, followers_count, following_count)
WHERE
  ha.id = data_set.user_id;
END
$BODY$
;
