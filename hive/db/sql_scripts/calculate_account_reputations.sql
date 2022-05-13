DROP TYPE IF EXISTS hivemind_app.AccountReputation CASCADE;

CREATE TYPE hivemind_app.AccountReputation AS (id int, reputation bigint, is_implicit boolean, changed boolean);

DROP FUNCTION IF EXISTS hivemind_app.calculate_account_reputations;

--- Massive version of account reputation calculation.
CREATE OR REPLACE FUNCTION hivemind_app.calculate_account_reputations(
  _first_block_num integer,
  _last_block_num integer,
  _tracked_account character varying DEFAULT NULL::character varying)
    RETURNS SETOF hivemind_app.accountreputation
    LANGUAGE 'plpgsql'
    STABLE 
AS $BODY$
DECLARE
  __vote_data RECORD;
  __account_reputations hivemind_app.AccountReputation[];
  __author_rep bigint;
  __new_author_rep bigint;
  __voter_rep bigint;
  __implicit_voter_rep boolean;
  __implicit_author_rep boolean;
  __rshares bigint;
  __prev_rshares bigint;
  __rep_delta bigint;
  __prev_rep_delta bigint;
  __traced_author int;
  __account_name varchar;
BEGIN
  SELECT INTO __account_reputations ARRAY(SELECT ROW(a.id, a.reputation, a.is_implicit, false)::hivemind_app.AccountReputation
  FROM hivemind_app.hive_accounts a
  WHERE a.id != 0
  ORDER BY a.id);

--  SELECT COALESCE((SELECT ha.id FROM hivemind_app.hive_accounts ha WHERE ha.name = _tracked_account), 0) INTO __traced_author;

  FOR __vote_data IN
    SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares,
      COALESCE((SELECT prd.rshares
                FROM hivemind_app.hive_reputation_data prd
                WHERE prd.author_id = rd.author_id and prd.voter_id = rd.voter_id
                      and prd.permlink = rd.permlink and prd.id < rd.id
                        ORDER BY prd.id DESC LIMIT 1), 0) as prev_rshares
      FROM hivemind_app.hive_reputation_data rd
      WHERE (_first_block_num IS NULL AND _last_block_num IS NULL) OR (rd.block_num BETWEEN _first_block_num AND _last_block_num)
      ORDER BY rd.id
    LOOP
      __voter_rep := __account_reputations[__vote_data.voter_id].reputation;
      __implicit_author_rep := __account_reputations[__vote_data.author_id].is_implicit;
    
/*      IF __vote_data.author_id = __traced_author THEN
           raise notice 'Processing vote <%> rshares: %, prev_rshares: %', __vote_data.id, __vote_data.rshares, __vote_data.prev_rshares;
       select ha.name into __account_name from hivemind_app.hive_accounts ha where ha.id = __vote_data.voter_id;
       raise notice 'Voter `%` (%) reputation: %', __account_name, __vote_data.voter_id,  __voter_rep;
      END IF;
*/
      CONTINUE WHEN __voter_rep < 0;

      __implicit_voter_rep := __account_reputations[__vote_data.voter_id].is_implicit;
    
      __author_rep := __account_reputations[__vote_data.author_id].reputation;
      __rshares := __vote_data.rshares;
      __prev_rshares := __vote_data.prev_rshares;
      __prev_rep_delta := (__prev_rshares >> 6)::bigint;

      IF NOT __implicit_author_rep AND --- Author must have set explicit reputation to allow its correction
         (__prev_rshares > 0 OR
          --- Voter must have explicitly set reputation to match hived old conditions
         (__prev_rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep - __prev_rep_delta)) THEN
            __author_rep := __author_rep - __prev_rep_delta;
            __implicit_author_rep := __author_rep = 0;
            __account_reputations[__vote_data.author_id] := ROW(__vote_data.author_id, __author_rep, __implicit_author_rep, true)::hivemind_app.AccountReputation;
 /*           IF __vote_data.author_id = __traced_author THEN
             raise notice 'Corrected author_rep by prev_rep_delta: % to have reputation: %', __prev_rep_delta, __author_rep;
            END IF;
*/
      END IF;

      __implicit_voter_rep := __account_reputations[__vote_data.voter_id].is_implicit;
      --- reread voter's rep. since it can change above if author == voter
    __voter_rep := __account_reputations[__vote_data.voter_id].reputation;
    
      IF __rshares > 0 OR
         (__rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep) THEN

        __rep_delta := (__rshares >> 6)::bigint;
        __new_author_rep = __author_rep + __rep_delta;
        __account_reputations[__vote_data.author_id] := ROW(__vote_data.author_id, __new_author_rep, False, true)::hivemind_app.AccountReputation;
/*        IF __vote_data.author_id = __traced_author THEN
          raise notice 'Changing account: <%> reputation from % to %', __vote_data.author_id, __author_rep, __new_author_rep;
        END IF;
*/
      ELSE
/*        IF __vote_data.author_id = __traced_author THEN
            raise notice 'Ignoring reputation change due to unmet conditions... Author_rep: %, Voter_rep: %', __author_rep, __voter_rep;
        END IF;
*/
      END IF;
    END LOOP;

    RETURN QUERY
      SELECT id, Reputation, is_implicit, changed
      FROM unnest(__account_reputations)
    WHERE Reputation IS NOT NULL and Changed 
    ;
END
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.calculate_account_reputations_for_block;

DROP TABLE IF EXISTS hivemind_app.__new_reputation_data;

CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app.__new_reputation_data
(
    id integer,
    author_id integer,
    voter_id integer,
    rshares bigint,
    prev_rshares bigint
);

DROP TABLE IF EXISTS hivemind_app.__tmp_accounts;

CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app.__tmp_accounts
(
    id integer,
    reputation bigint,
    is_implicit boolean,
    changed boolean
);

CREATE OR REPLACE FUNCTION hivemind_app.calculate_account_reputations_for_block(_block_num INT, _tracked_account VARCHAR DEFAULT NULL::VARCHAR)
  RETURNS SETOF hivemind_app.accountreputation
  LANGUAGE 'plpgsql'
  VOLATILE
AS $BODY$
DECLARE
  __vote_data RECORD;
  __author_rep bigint;
  __new_author_rep bigint;
  __voter_rep bigint;
  __implicit_voter_rep boolean;
  __implicit_author_rep boolean;
  __author_rep_changed boolean := false;
  __rshares bigint;
  __prev_rshares bigint;
  __rep_delta bigint;
  __prev_rep_delta bigint;
  __traced_author int;
  __account_name varchar;
BEGIN

  DELETE FROM hivemind_app.__new_reputation_data;

  INSERT INTO hivemind_app.__new_reputation_data
    SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares,
      COALESCE((SELECT prd.rshares
               FROM hivemind_app.hive_reputation_data prd
               WHERE prd.author_id = rd.author_id AND prd.voter_id = rd.voter_id
                     AND prd.permlink = rd.permlink AND prd.id < rd.id
                      ORDER BY prd.id DESC LIMIT 1), 0) AS prev_rshares
    FROM hivemind_app.hive_reputation_data rd
    WHERE rd.block_num = _block_num
    ORDER BY rd.id
    ;


  DELETE FROM hivemind_app.__tmp_accounts;

  INSERT INTO hivemind_app.__tmp_accounts
  SELECT ha.id, ha.reputation, ha.is_implicit, false AS changed
  FROM hivemind_app.__new_reputation_data rd
  JOIN hivemind_app.hive_accounts ha on rd.author_id = ha.id
  UNION
  SELECT hv.id, hv.reputation, hv.is_implicit, false as changed
  FROM hivemind_app.__new_reputation_data rd
  JOIN hivemind_app.hive_accounts hv on rd.voter_id = hv.id
  ;

--  SELECT COALESCE((SELECT ha.id FROM hivemind_app.hive_accounts ha WHERE ha.name = _tracked_account), 0) INTO __traced_author;

  FOR __vote_data IN
      SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares, rd.prev_rshares
      FROM hivemind_app.__new_reputation_data rd
      ORDER BY rd.id
    LOOP
      SELECT INTO __voter_rep, __implicit_voter_rep ha.reputation, ha.is_implicit 
      FROM hivemind_app.__tmp_accounts ha where ha.id = __vote_data.voter_id;
      SELECT INTO __author_rep, __implicit_author_rep ha.reputation, ha.is_implicit 
      FROM hivemind_app.__tmp_accounts ha where ha.id = __vote_data.author_id;

/*      IF __vote_data.author_id = __traced_author THEN
           raise notice 'Processing vote <%> rshares: %, prev_rshares: %', __vote_data.id, __vote_data.rshares, __vote_data.prev_rshares;
       select ha.name into __account_name from hivemind_app.hive_accounts ha where ha.id = __vote_data.voter_id;
       raise notice 'Voter `%` (%) reputation: %', __account_name, __vote_data.voter_id,  __voter_rep;
      END IF;
*/
      CONTINUE WHEN __voter_rep < 0;
    
      __rshares := __vote_data.rshares;
      __prev_rshares := __vote_data.prev_rshares;
      __prev_rep_delta := (__prev_rshares >> 6)::bigint;

      IF NOT __implicit_author_rep AND --- Author must have set explicit reputation to allow its correction
         (__prev_rshares > 0 OR
          --- Voter must have explicitly set reputation to match hived old conditions
         (__prev_rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep - __prev_rep_delta)) THEN
            __author_rep := __author_rep - __prev_rep_delta;
            __implicit_author_rep := __author_rep = 0;
            __author_rep_changed = true;
            if __vote_data.author_id = __vote_data.voter_id THEN
              __implicit_voter_rep := __implicit_author_rep;
              __voter_rep := __author_rep;
            end if;

 /*           IF __vote_data.author_id = __traced_author THEN
             raise notice 'Corrected author_rep by prev_rep_delta: % to have reputation: %', __prev_rep_delta, __author_rep;
            END IF;
*/
      END IF;
    
      IF __rshares > 0 OR
         (__rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep) THEN

        __rep_delta := (__rshares >> 6)::bigint;
        __new_author_rep = __author_rep + __rep_delta;
        __author_rep_changed = true;

        UPDATE hivemind_app.__tmp_accounts
        SET reputation = __new_author_rep,
            is_implicit = False,
            changed = true
        WHERE id = __vote_data.author_id;

/*        IF __vote_data.author_id = __traced_author THEN
          raise notice 'Changing account: <%> reputation from % to %', __vote_data.author_id, __author_rep, __new_author_rep;
        END IF;
*/
      ELSE
/*        IF __vote_data.author_id = __traced_author THEN
            raise notice 'Ignoring reputation change due to unmet conditions... Author_rep: %, Voter_rep: %', __author_rep, __voter_rep;
        END IF;
*/
      END IF;
    END LOOP;

    RETURN QUERY SELECT id, reputation, is_implicit, Changed
    FROM hivemind_app.__tmp_accounts
    WHERE Reputation IS NOT NULL AND Changed 
    ;
END
$BODY$
;

DROP FUNCTION IF EXISTS hivemind_app.truncate_account_reputation_data;

CREATE OR REPLACE FUNCTION hivemind_app.truncate_account_reputation_data(
  in _day_limit INTERVAL,
  in _allow_truncate BOOLEAN)
  RETURNS VOID 
  LANGUAGE 'plpgsql'
  VOLATILE 
AS $BODY$
DECLARE
  __block_num_limit INT;

BEGIN
  __block_num_limit = hivemind_app.block_before_head(_day_limit);
  
  IF _allow_truncate THEN
    DROP TABLE IF EXISTS hivemind_app.__actual_reputation_data;
    CREATE UNLOGGED TABLE IF NOT EXISTS hivemind_app.__actual_reputation_data
    AS
    SELECT * FROM hivemind_app.hive_reputation_data hrd
    WHERE hrd.block_num >= __block_num_limit;

    TRUNCATE TABLE hivemind_app.hive_reputation_data;
    INSERT INTO hivemind_app.hive_reputation_data
    SELECT * FROM hivemind_app.__actual_reputation_data;

    TRUNCATE TABLE hivemind_app.__actual_reputation_data;
    DROP TABLE IF EXISTS hivemind_app.__actual_reputation_data;
  ELSE
    DELETE FROM hivemind_app.hive_reputation_data hpd
    WHERE hpd.block_num < __block_num_limit
    ;
  END IF;
END
$BODY$
;


DROP FUNCTION IF EXISTS hivemind_app.update_account_reputations;

CREATE OR REPLACE FUNCTION hivemind_app.update_account_reputations(
  in _first_block_num INTEGER,
  in _last_block_num INTEGER,
  in _force_data_truncate BOOLEAN)
  RETURNS VOID 
  LANGUAGE 'plpgsql'
  VOLATILE 
AS $BODY$
DECLARE
  __truncate_interval interval := '30 days'::interval;
  __truncate_block_count INT := 1*24*1200*3; --- 1day

BEGIN
  UPDATE hivemind_app.hive_accounts urs
  SET reputation = ds.reputation,
      is_implicit = ds.is_implicit
  FROM 
  (
    SELECT p.id as account_id, p.reputation, p.is_implicit
    FROM hivemind_app.calculate_account_reputations(_first_block_num, _last_block_num) p
    WHERE _first_block_num IS NULL OR _last_block_num IS NULL OR _first_block_num != _last_block_num

    UNION ALL

    SELECT p.id as account_id, p.reputation, p.is_implicit
    FROM hivemind_app.calculate_account_reputations_for_block(_first_block_num) p
    WHERE _first_block_num IS NOT NULL AND _last_block_num IS NOT NULL AND _first_block_num = _last_block_num

  ) ds
  WHERE urs.id = ds.account_id AND (urs.reputation != ds.reputation OR urs.is_implicit != ds.is_implicit)
  ;

  IF _force_data_truncate or _last_block_num IS NULL OR MOD(_last_block_num, __truncate_block_count) = 0 THEN
    PERFORM hivemind_app.truncate_account_reputation_data(__truncate_interval, _force_data_truncate);
  END IF
  ;
END
$BODY$
;

