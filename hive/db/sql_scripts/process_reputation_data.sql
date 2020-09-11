DROP FUNCTION IF EXISTS process_reputation_data(in _block_num hive_blocks.num%TYPE, in _author hive_accounts.name%TYPE,
  in _permlink hive_permlink_data.permlink%TYPE, in _voter hive_accounts.name%TYPE, in _rshares hive_votes.rshares%TYPE)
  ;

CREATE OR REPLACE FUNCTION process_reputation_data(in _block_num hive_blocks.num%TYPE,
  in _author hive_accounts.name%TYPE, in _permlink hive_permlink_data.permlink%TYPE,
  in _voter hive_accounts.name%TYPE, in _rshares hive_votes.rshares%TYPE)
RETURNS void
LANGUAGE sql
VOLATILE 
AS $BODY$
  WITH __insert_info AS (
    INSERT INTO hive_reputation_data
      (author_id, voter_id, permlink, block_num, rshares)
    --- Warning DISTINCT is needed here since we have to strict join to hv table and there is really made a CROSS JOIN
    --- between ha and hv records (producing 2 duplicated records)
    SELECT DISTINCT ha.id as author_id, hv.id as voter_id, _permlink, _block_num, _rshares
    FROM hive_accounts ha
    JOIN hive_accounts hv ON hv.name = _voter
    JOIN hive_posts hp ON hp.author_id = ha.id
    JOIN hive_permlink_data hpd ON hp.permlink_id = hpd.id
    WHERE hpd.permlink = _permlink
          AND ha.name = _author

          AND NOT hp.is_paidout --- voting on paidout posts shall have no effect
          AND hv.reputation >= 0 --- voter's negative reputation eliminates vote from processing
          AND (_rshares >= 0 
                OR (hv.reputation >= (ha.reputation - COALESCE((SELECT (hrd.rshares >> 6) -- if previous vote was a downvote we need to correct author reputation before current comparison to voter's reputation
                                                              FROM hive_reputation_data hrd
                                                              WHERE hrd.author_id = ha.id
                                                                    AND hrd.voter_id=hv.id
                                                                    AND hrd.permlink=_permlink
                                                                    AND hrd.rshares < 0), 0)))
              )
    ON CONFLICT ON CONSTRAINT hive_reputation_data_uk DO
    UPDATE SET
      rshares = EXCLUDED.rshares
    RETURNING (xmax = 0) AS is_new_vote, 
              (SELECT hrd.rshares
              FROM hive_reputation_data hrd
              --- Warning we want OLD row here, not both, so we're using old ID to select old one (new record has different value) !!!
              WHERE hrd.id = hive_reputation_data.id AND hrd.author_id = author_id and hrd.voter_id=voter_id and hrd.permlink=_permlink) AS old_rshares, author_id, voter_id
  )
UPDATE hive_accounts uha
  SET reputation = CASE __insert_info.is_new_vote
                      WHEN true THEN ha.reputation + (_rshares >> 6)
                      ELSE ha.reputation - (__insert_info.old_rshares >> 6) + (_rshares >> 6)
                    END
  FROM hive_accounts ha
  JOIN __insert_info ON ha.id = __insert_info.author_id
  WHERE uha.id = __insert_info.author_id
  ;
$BODY$;