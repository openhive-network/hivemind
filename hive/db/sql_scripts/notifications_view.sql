DROP FUNCTION IF EXISTS hivemind_app.calculate_notify_vote_score(_payout hivemind_app.hive_posts.payout%TYPE, _abs_rshares hivemind_app.hive_posts.abs_rshares%TYPE, _rshares hivemind_app.hive_votes.rshares%TYPE) CASCADE
;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_notify_vote_score(_payout hivemind_app.hive_posts.payout%TYPE, _abs_rshares hivemind_app.hive_posts.abs_rshares%TYPE, _rshares hivemind_app.hive_votes.rshares%TYPE)
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

DROP FUNCTION IF EXISTS hivemind_app.notification_id CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.notification_id(in _block_number INTEGER, in _notifyType INTEGER, in _id INTEGER)
RETURNS BIGINT
AS
$function$
BEGIN
RETURN CAST( _block_number as BIGINT ) << 36
       | ( _notifyType << 28 )
       | ( _id & CAST( x'0FFFFFFF' as BIGINT) );
END
$function$
LANGUAGE plpgsql IMMUTABLE
;

DROP FUNCTION IF EXISTS hivemind_app.calculate_value_of_vote_on_post CASCADE;
CREATE OR REPLACE FUNCTION hivemind_app.calculate_value_of_vote_on_post(
    _post_payout hivemind_app.hive_posts.payout%TYPE
  , _post_rshares hivemind_app.hive_posts.vote_rshares%TYPE
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

--vote has own score, new communities score as 35 (magic number), persistent notifications are already scored
DROP VIEW IF EXISTS hivemind_app.hive_raw_notifications_view_no_account_score cascade;
CREATE OR REPLACE VIEW hivemind_app.hive_raw_notifications_view_no_account_score
AS
  SELECT --persistent notifs
       hn.block_num
     , hn.post_id as post_id
     , hn.type_id as type_id
     , hn.created_at as created_at
     , hn.src_id as src
     , hn.dst_id as dst
     , hn.post_id as dst_post_id
     , hc.name as community
     , hc.title as community_title
     , hn.payload as payload
     , hn.score as score
  FROM hivemind_app.hive_notifs hn
  JOIN hivemind_app.hive_communities hc ON hn.community_id = hc.id
;

DROP VIEW IF EXISTS hivemind_app.hive_raw_notifications_view CASCADE;
CREATE OR REPLACE VIEW hivemind_app.hive_raw_notifications_view
AS
SELECT *
FROM
  (
  SELECT * FROM hivemind_app.hive_raw_notifications_view_no_account_score
  ) as notifs
WHERE notifs.score >= 0 AND notifs.src IS DISTINCT FROM notifs.dst;
