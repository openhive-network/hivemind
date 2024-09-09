DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.valid_follow_type;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.valid_follow_type(_follow_type TEXT)
  RETURNS INT
  LANGUAGE plpgsql
  IMMUTABLE
AS
$BODY$
BEGIN
  CASE
      WHEN _follow_type = 'blog' THEN
          RETURN 1;
      WHEN _follow_type = 'ignore' THEN
          RETURN 2;
      ELSE
          RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_invalid_community_type_exception();
  END CASE;
END;
$BODY$
;