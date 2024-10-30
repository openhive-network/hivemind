DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_muted_reason_map;
CREATE FUNCTION hivemind_postgrest_utilities.get_muted_reason_map()
  RETURNS JSONB
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  RETURN jsonb_build_object(
    'MUTED_COMMUNITY_MODERATION', 0,
    'MUTED_COMMUNITY_TYPE', 1,
    'MUTED_PARENT', 2,
    'MUTED_REPUTATION', 3,
    'MUTED_ROLE_COMMUNITY', 4
  );
END;
$BODY$
;

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