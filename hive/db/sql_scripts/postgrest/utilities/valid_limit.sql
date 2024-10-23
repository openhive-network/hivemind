DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_limit;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.valid_limit(_limit INT, _ubound INT, _default_num INT)
RETURNS INT
LANGUAGE plpgsql
STABLE
AS
$BODY$
BEGIN
  RETURN hivemind_postgrest_utilities.valid_number(_limit, _default_num, 1, _ubound);
END;
$BODY$
;