DROP FUNCTION IF EXISTS public.max_time_stamp() CASCADE;
CREATE OR REPLACE FUNCTION public.max_time_stamp( _first TIMESTAMP, _second TIMESTAMP )
RETURNS TIMESTAMP
LANGUAGE 'plpgsql'
IMMUTABLE
AS $BODY$
BEGIN
  IF _first > _second THEN
        RETURN _first;
    ELSE
        RETURN _second;
    END IF;
END
$BODY$;