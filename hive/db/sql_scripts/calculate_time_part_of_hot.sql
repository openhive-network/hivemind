DROP FUNCTION IF EXISTS public.calculate_time_part_of_hot(_post_created_at hive_posts.created_at%TYPE ) CASCADE
;
CREATE OR REPLACE FUNCTION public.calculate_time_part_of_hot(
  _post_created_at hive_posts.created_at%TYPE)
    RETURNS double precision
    LANGUAGE 'plpgsql'
    IMMUTABLE
AS $BODY$
DECLARE
  result double precision;
  sec_from_epoch INT = 0;
BEGIN
  sec_from_epoch  = date_diff( 'second', CAST('19700101' AS TIMESTAMP), _post_created_at );
  result = sec_from_epoch/10000.0;
  return result;
END;
$BODY$;