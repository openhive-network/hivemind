DROP FUNCTION IF EXISTS hivemind_utilities.valid_tag;
CREATE FUNCTION hivemind_utilities.valid_tag(in _tag TEXT, _allow_empty BOOLEAN DEFAULT FALSE)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS
$BODY$
BEGIN
  IF _tag IS NULL OR _tag = '' THEN
    IF NOT _allow_empty THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('tag was blank');
    END IF;
    RETURN _tag;
  END IF;
  IF NOT _tag ~ '^[a-z0-9_]' THEN
    RAISE EXCEPTION '%', hivemind_utilities.raise_parameter_validation_exception('invalid tag `' || _tag || '`');
  END IF;
  RETURN _tag;
END;
$BODY$
;