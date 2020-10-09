DROP FUNCTION IF EXISTS public.find_tag_id CASCADE;
CREATE OR REPLACE FUNCTION public.find_tag_id(
    in _tag_name hive_tag_data.tag%TYPE,
    in _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$BODY$
DECLARE
  __tag_id INTEGER;
BEGIN
  SELECT INTO __tag_id COALESCE( ( SELECT id FROM hive_tag_data WHERE tag=_tag_name ), 0 );
  IF _check AND __tag_id = 0 THEN
      RAISE EXCEPTION 'Tag % does not exist', _tag_name;
  END IF;
  RETURN __tag_id;
END
$BODY$
;

DROP FUNCTION IF EXISTS public.find_category_id CASCADE;
CREATE OR REPLACE FUNCTION public.find_category_id(
    in _category_name hive_category_data.category%TYPE,
    in _check BOOLEAN
)
RETURNS INTEGER
LANGUAGE 'plpgsql' STABLE
AS
$BODY$
DECLARE
  __category_id INTEGER;
BEGIN
  SELECT INTO __category_id COALESCE( ( SELECT id FROM hive_category_data WHERE category=_category_name ), 0 );
  IF _check AND __category_id = 0 THEN
      RAISE EXCEPTION 'Category % does not exist', _category_name;
  END IF;
  RETURN __category_id;
END
$BODY$
;
