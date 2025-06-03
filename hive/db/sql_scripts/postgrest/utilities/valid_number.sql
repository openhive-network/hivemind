DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_number;
CREATE FUNCTION hivemind_postgrest_utilities.valid_number(
  _num INT,
  _default_num INT,
  _lbound INT DEFAULT NULL,
  _ubound INT DEFAULT NULL,
  _name TEXT DEFAULT 'integer value'
)
  RETURNS INT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _num IS NULL THEN
    IF _default_num IS NULL THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_name || ' must be provided');
    ELSE
      _num = _default_num;
    END IF;
  END IF;

  IF _lbound IS NOT NULL AND _num < _lbound THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_name || ' = ' || _num || ' outside valid range [' || _lbound || ':' || _ubound ||']');
  END IF;
  IF _ubound IS NOT NULL AND _num > _ubound THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_name || ' = ' || _num || ' outside valid range [' || _lbound || ':' || _ubound ||']');
  END IF;

  RETURN _num;
END;
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_bigint;
CREATE FUNCTION hivemind_postgrest_utilities.valid_bigint(
  _num BIGINT,
  _default_num BIGINT,
  _lbound BIGINT DEFAULT NULL,
  _ubound BIGINT DEFAULT NULL,
  _name TEXT DEFAULT 'integer value'
)
  RETURNS BIGINT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _num IS NULL THEN
    IF _default_num IS NULL THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_name || ' must be provided');
    ELSE
      _num = _default_num;
    END IF;
  END IF;

  IF _lbound IS NOT NULL AND _num < _lbound THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_name || ' = ' || _num || ' outside valid range [' || _lbound || ':' || _ubound ||']');
  END IF;
  IF _ubound IS NOT NULL AND _num > _ubound THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_name || ' = ' || _num || ' outside valid range [' || _lbound || ':' || _ubound ||']');
  END IF;

  RETURN _num;
END;
$BODY$
;
