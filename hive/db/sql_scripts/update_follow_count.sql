DROP FUNCTION IF EXISTS hivemind_app.update_follow_count(hive_blocks.num%TYPE, hivemind_app.hive_blocks.num%TYPE);
CREATE OR REPLACE FUNCTION hivemind_app.update_follow_count(
  in _first_block hivemind_app.hive_blocks.num%TYPE,
  in _last_block hivemind_app.hive_blocks.num%TYPE
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
    WITH data_cfe(user_id) AS (
      SELECT DISTINCT following FROM hivemind_app.hive_follows WHERE block_num BETWEEN _first_block AND _last_block
      UNION 
      SELECT DISTINCT follower FROM hivemind_app.hive_follows WHERE block_num BETWEEN _first_block AND _last_block
    )
    SELECT
        data_cfe.user_id AS user_id,
        (SELECT COUNT(1) FROM hivemind_app.hive_follows hf1 WHERE hf1.following = data_cfe.user_id AND hf1.state = 1) AS followers_count,
        (SELECT COUNT(1) FROM hivemind_app.hive_follows hf2 WHERE hf2.follower = data_cfe.user_id AND hf2.state = 1) AS following_count
    FROM
        data_cfe
  ) AS data_set(user_id, followers_count, following_count)
WHERE
  ha.id = data_set.user_id;
END
$BODY$
;