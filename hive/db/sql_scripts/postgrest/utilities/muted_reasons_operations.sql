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

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.create_muted_reasons_bitmask;
CREATE FUNCTION hivemind_postgrest_utilities.create_muted_reasons_bitmask(IN _reasons INT[])
RETURNS INTEGER
LANGUAGE 'plpgsql'
IMMUTABLE
AS
$BODY$
DECLARE
  _mask INT DEFAULT 0;
  _reason INT;
BEGIN
  -- NULL or empty array means no filter
  IF _reasons IS NULL OR array_length(_reasons, 1) IS NULL THEN
    RETURN NULL;
  END IF;

  -- Build bitmask from array
  FOREACH _reason IN ARRAY _reasons
  LOOP
    -- Validate range 0-4
    IF _reason < 0 OR _reason > 4 THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(
        FORMAT('Invalid muted reason: %s. Must be between 0-4.', _reason)
      );
    END IF;

    -- Set the bit
    _mask := _mask | (1 << _reason);
  END LOOP;

  RETURN _mask;
END
$BODY$
;