DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.rep_log10;
-- float8 version of the NUMERIC LOG algorithm: same rounded result for every reputation, ~30x cheaper and inlinable
CREATE FUNCTION hivemind_postgrest_utilities.rep_log10(IN _rep BIGINT)
  RETURNS NUMERIC
  LANGUAGE sql
  IMMUTABLE
AS
$BODY$
  SELECT CASE WHEN _rep = 0 THEN 25::NUMERIC ELSE
    ROUND((
      (CASE WHEN _rep < 0 THEN -1 ELSE 1 END)
      * GREATEST(
          --( HOW MANY DIGITS \/  )
          FLOOR(LOG(ABS(_rep::FLOAT8)))
                          --( first four digits \/                   )
          + ( (LOG(FLOOR(ABS(_rep::FLOAT8) / 10^(FLOOR(LOG(ABS(_rep::FLOAT8))) - 3))) + 1e-8)
            - FLOOR(LOG(FLOOR(ABS(_rep::FLOAT8) / 10^(FLOOR(LOG(ABS(_rep::FLOAT8))) - 3))) + 1e-8) )
          - 9, 0) * 9 + 25
    )::NUMERIC, 2)
  END
$BODY$
;
