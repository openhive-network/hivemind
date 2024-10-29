DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.validate_community_sort_type;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.validate_community_sort_type(_sort_type TEXT)
  RETURNS TEXT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
    IF _sort_type NOT IN ('rank', 'new', 'subs') THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_community_exception('Unsupported sort, valid sorts: rank, new, subs');
    END IF;

    RETURN _sort_type;
END;
$BODY$
;