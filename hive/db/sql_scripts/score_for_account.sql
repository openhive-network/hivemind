DROP FUNCTION IF EXISTS score_for_account(in _account_id hive_accounts.id%TYPE)
;
CREATE OR REPLACE FUNCTION score_for_account(in _account_id hive_accounts.id%TYPE)
RETURNS SMALLINT
AS
$function$
DECLARE
  score SMALLINT;
BEGIN
  SELECT INTO score
      CASE
          WHEN rank.position < 200 THEN 70
          WHEN rank.position < 1000 THEN 60
          WHEN rank.position < 6500 THEN 50
          WHEN rank.position < 25000 THEN 40
          WHEN rank.position < 100000 THEN 30
          ELSE 20
      END as score
  FROM (
      SELECT
          (
              SELECT COUNT(*)
              FROM hive_accounts ha_for_rank2
              WHERE ha_for_rank2.reputation > ha_for_rank.reputation
          ) as position
      FROM hive_accounts ha_for_rank WHERE ha_for_rank.id = _account_id
  ) as rank;
  return score;
END
$function$
LANGUAGE plpgsql
;