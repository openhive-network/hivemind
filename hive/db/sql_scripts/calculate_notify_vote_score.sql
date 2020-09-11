DROP FUNCTION IF EXISTS public.calculate_notify_vote_score(_payout hive_posts.payout%TYPE, _abs_rshares hive_posts_view.abs_rshares%TYPE, _rshares hive_votes.rshares%TYPE) CASCADE
;
CREATE OR REPLACE FUNCTION public.calculate_notify_vote_score(_payout hive_posts.payout%TYPE, _abs_rshares hive_posts_view.abs_rshares%TYPE, _rshares hive_votes.rshares%TYPE)
RETURNS INT
LANGUAGE 'sql'
IMMUTABLE
AS $BODY$
    SELECT CASE
        WHEN ((( _payout )/_abs_rshares) * 1000 * _rshares < 20 ) THEN -1
        ELSE LEAST(100, (LENGTH(CAST( ( (( _payout )/_abs_rshares) * 1000 * _rshares ) as text)) - 1) * 25)
    END;
$BODY$;