DROP FUNCTION IF EXISTS hivemind_utilities.valid_permlink;
CREATE FUNCTION hivemind_utilities.valid_permlink(
  _permlink TEXT,
  _allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  IF _permlink IS NULL OR _permlink = '' THEN
    IF NOT _allow_empty THEN
      RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_permlink_exception('permlink cannot be blank');
    END IF;

    RETURN _permlink;
  END IF;

  IF LENGTH(_permlink) <= 256 THEN
    RETURN _permlink;
  ELSE
    RAISE EXCEPTION '%', hivemind_utilities.raise_invalid_permlink_exception('invalid permlink length');
  END IF;

END;
$BODY$
;