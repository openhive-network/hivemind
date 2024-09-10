DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_community;
CREATE FUNCTION hivemind_postgrest_utilities.valid_community(
  _name TEXT,
  allow_empty BOOLEAN DEFAULT FALSE
)
  RETURNS TEXT
  LANGUAGE plpgsql
  STABLE
AS
$BODY$
BEGIN
  IF _name IS NULL OR _name = '' THEN
    IF NOT allow_empty THEN
      RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_community_exception('community name cannot be blank');
    END IF;

    RETURN _name;
  END IF;

  IF NOT hivemind_postgrest_utilities.check_community(_name) THEN
    RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_community_exception('given community name is not valid');
  END IF;

  RETURN _name;
END;
$BODY$
;