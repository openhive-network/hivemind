DROP FUNCTION IF EXISTS hivemind_utilities.valid_offset;
CREATE FUNCTION hivemind_utilities.valid_offset(IN _offset INT, IN _ubound INT DEFAULT NULL)
  RETURNS INT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _offset >= -1 THEN
    IF _ubound IS NOT NULL AND _offset > _ubound THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('offset too large');
    ELSE
      RETURN _offset;
    END IF;
  ELSE
    RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('offset cannot be negative');
  END IF;
END;
$BODY$
;