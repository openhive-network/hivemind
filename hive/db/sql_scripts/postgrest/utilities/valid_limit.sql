DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_limit;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.valid_limit(
  _limit NUMERIC,
  ubound INT,
  default_num INT
)
  RETURNS INT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  RETURN hivemind_postgrest_utilities.valid_number(_limit, default_num, 'limit', 1, ubound);
END;
$BODY$
;