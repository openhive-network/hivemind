DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.decode_muted_reasons_mask;
CREATE FUNCTION hivemind_postgrest_utilities.decode_muted_reasons_mask(IN _mask BIGINT)
  RETURNS JSONB
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
DECLARE
_result JSONB DEFAULT '[]'::jsonb;
BEGIN
  IF _mask < 0 THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('Mask cannot be negative');
  END IF;

  FOR i IN 0..31 LOOP
    IF (_mask & (1 << i)) <> 0 THEN
      _result = _result || jsonb_build_array(i);
    END IF;
  END LOOP;

  RETURN _result;
END;
$BODY$
;