DROP FUNCTION IF EXISTS get_number_of_unreaded_notifications;
CREATE OR REPLACE FUNCTION get_number_of_unreaded_notifications(in _account VARCHAR, in _minimum_score SMALLINT)
RETURNS TABLE( lastread_at TIMESTAMP, unread BIGINT )
LANGUAGE 'sql' STABLE
AS
$BODY$
SELECT
  ha.lastread_at as lastread_at,
  COUNT(1) as unread
FROM
  hive_notifications_view hnv
  JOIN hive_accounts ha
  ON ha.name = hnv.dst
  WHERE hnv.created_at > ha.lastread_at AND hnv.score >= _minimum_score AND hnv.dst = _account
  GROUP BY ha.lastread_at
$BODY$
;
