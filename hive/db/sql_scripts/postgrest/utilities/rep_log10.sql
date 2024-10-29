DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.rep_log10;
CREATE FUNCTION hivemind_postgrest_utilities.rep_log10(IN _rep BIGINT)
  RETURNS NUMERIC
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
DECLARE
_rep_is_negative BOOLEAN DEFAULT FALSE;
_result NUMERIC;
BEGIN
  IF _rep = 0 THEN
    RETURN 25;
  END IF;

  IF _rep < 0 THEN
    _rep_is_negative = True;
    _rep = @_rep;
  END IF;

                  --( first four digits \/                   )
  _result = LOG(10, FLOOR(_rep / 10^(FLOOR(LOG(10, _rep) - 3)))) + 0.00000001;
          --( HOW MANY DIGITS \/  )
  _result = (FLOOR(LOG10(_rep) + 1) - 1) + (_result - FLOOR(_result));

  _result = GREATEST(_result - 9, 0);
  IF _rep_is_negative THEN
    _result = -_result;
  END IF;

  _result = (_result * 9) + 25;
  _result = ROUND(_result, 2);
  RETURN _result;
END;
$BODY$
;