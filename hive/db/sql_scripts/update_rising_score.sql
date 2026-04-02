DROP FUNCTION IF EXISTS hivemind_app.update_rising_scores;
CREATE FUNCTION hivemind_app.update_rising_scores()
RETURNS void
AS
$function$
UPDATE hivemind_app.hive_posts SET
  sc_rising = CASE
    WHEN snapshot_at = '1970-01-01' THEN 0  -- first pass: set baseline only
    ELSE (vote_rshares - rshares_snapshot)::REAL
         / GREATEST(EXTRACT(EPOCH FROM (now() - snapshot_at)) / 3600.0, 0.1)
  END,
  rshares_snapshot = vote_rshares,
  snapshot_at = now()
WHERE NOT is_paidout
  AND counter_deleted = 0
  AND depth = 0
  AND created_at > now() - interval '7 days';
$function$
language sql;

DROP FUNCTION IF EXISTS hivemind_app.initialize_rising_scores;
CREATE FUNCTION hivemind_app.initialize_rising_scores()
RETURNS void
AS
$function$
UPDATE hivemind_app.hive_posts SET
  sc_rising = 0,
  rshares_snapshot = vote_rshares,
  snapshot_at = now()
WHERE NOT is_paidout
  AND counter_deleted = 0
  AND depth = 0;
$function$
language sql;
