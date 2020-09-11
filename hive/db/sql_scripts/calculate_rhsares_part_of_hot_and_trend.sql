DROP FUNCTION IF EXISTS public.calculate_rhsares_part_of_hot_and_trend(_rshares hive_votes.rshares%TYPE) CASCADE
;
CREATE OR REPLACE FUNCTION public.calculate_rhsares_part_of_hot_and_trend(_rshares hive_votes.rshares%TYPE)
RETURNS double precision
LANGUAGE 'plpgsql'
IMMUTABLE
AS $BODY$
DECLARE
    mod_score double precision;
BEGIN
    mod_score := _rshares / 10000000.0;
    IF ( mod_score > 0 )
    THEN
        return log( greatest( abs(mod_score), 1 ) );
    END IF;
    return  -1.0 * log( greatest( abs(mod_score), 1 ) );
END;
$BODY$;