DROP FUNCTION IF EXISTS hivemind_app.calculate_notify_vote_score(_payout hivemind_app.hive_posts.payout%TYPE, _abs_rshares hivemind_app.hive_posts_rshares.abs_rshares%TYPE, _rshares hivemind_app.hive_votes.rshares%TYPE) CASCADE
;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_notify_vote_score(_payout hivemind_app.hive_posts.payout%TYPE, _abs_rshares hivemind_app.hive_posts_rshares.abs_rshares%TYPE, _rshares hivemind_app.hive_votes.rshares%TYPE)
RETURNS INT
LANGUAGE 'sql'
IMMUTABLE
AS $BODY$
  SELECT CASE _abs_rshares = 0
    WHEN TRUE THEN CAST(0 AS INT)
    ELSE CASE
        WHEN ((( _payout )/_abs_rshares) * 1000 * _rshares < 20 ) THEN -1
        ELSE LEAST(100, (LENGTH(CAST( CAST( ( (( _payout )/_abs_rshares) * 1000 * _rshares ) as BIGINT) as text)) - 1) * 25)
      END
  END;
$BODY$;

DROP FUNCTION IF EXISTS hivemind_app.calculate_value_of_vote_on_post CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_value_of_vote_on_post(
    _post_payout hivemind_app.hive_posts.payout%TYPE
  , _post_rshares hivemind_app.hive_posts_rshares.vote_rshares%TYPE
  , _vote_rshares hivemind_app.hive_votes.rshares%TYPE)
RETURNS FLOAT
LANGUAGE 'sql'
IMMUTABLE
AS $BODY$
    SELECT CASE _post_rshares != 0
              WHEN TRUE THEN CAST( ( _post_payout/_post_rshares ) * _vote_rshares as FLOAT)
           ELSE
              CAST(0 AS FLOAT)
           END
$BODY$;

DROP FUNCTION IF EXISTS hivemind_app.format_vote_value_payload CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.format_vote_value_payload(
    _vote_value FLOAT
)
RETURNS VARCHAR
LANGUAGE 'sql'
IMMUTABLE
AS $BODY$
    SELECT CASE
        WHEN _vote_value < 0.01 THEN ''::VARCHAR
        ELSE CAST( to_char(_vote_value, '($FM99990.00)') AS VARCHAR )
    END
$BODY$;
