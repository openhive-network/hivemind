DROP TYPE IF EXISTS AccountReputation CASCADE;

CREATE TYPE AccountReputation AS (id int, reputation bigint, is_implicit boolean, changed boolean);

DROP FUNCTION IF EXISTS public.calculate_account_reputations;

-- FUNCTION: public.calculate_account_reputations(integer, integer, character varying)

-- DROP FUNCTION public.calculate_account_reputations(integer, integer, character varying);

CREATE OR REPLACE FUNCTION public.calculate_account_reputations(
	_first_block_num integer,
	_last_block_num integer,
	_tracked_account character varying DEFAULT NULL::character varying)
    RETURNS SETOF accountreputation 
    LANGUAGE 'plpgsql'

    COST 100
    volatile 
    ROWS 1000
AS $BODY$
DECLARE
  __vote_data RECORD;
  __account_reputations AccountReputation[];
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

  IF _first_block_num IS NULL AND _last_block_num IS NULL THEN
    SELECT INTO __account_reputations ARRAY(SELECT ROW(a.id, a.reputation, a.is_implicit, false)::AccountReputation
    FROM hive_accounts a
    WHERE a.id != 0 
    ORDER BY a.id);
  else
    truncate table __new_reputation_data;
    insert into __new_reputation_data 
      SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares,
        COALESCE((SELECT prd.rshares
                FROM hive_reputation_data prd
                WHERE prd.author_id = rd.author_id and prd.voter_id = rd.voter_id
                      and prd.permlink = rd.permlink and prd.id < rd.id
                        ORDER BY prd.id DESC LIMIT 1), 0) as prev_rshares
      FROM hive_reputation_data rd 
      WHERE rd.block_num BETWEEN _first_block_num AND _last_block_num
      ORDER BY rd.id
      ;

    truncate table __tmp_accounts;
    insert into __tmp_accounts
    select ha.id, ha.reputation, ha.is_implicit, false as changed
    from __new_reputation_data rd
    join hive_accounts ha on rd.author_id = ha.id
    union
    select hv.id, hv.reputation, hv.is_implicit, false as changed
    from __new_reputation_data rd
    join hive_accounts hv on rd.voter_id = hv.id
    ;
  END IF;

--  SELECT COALESCE((SELECT ha.id FROM hive_accounts ha WHERE ha.name = _tracked_account), 0) INTO __traced_author;

  FOR __vote_data IN
      SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares, rd.prev_rshares
      FROM __new_reputation_data rd 
      ORDER BY rd.id
    LOOP
      IF _first_block_num IS NULL AND _last_block_num IS NULL THEN
          __voter_rep := __account_reputations[__vote_data.voter_id].reputation;
         __implicit_voter_rep := __account_reputations[__vote_data.voter_id].is_implicit;	  
         __implicit_author_rep := __account_reputations[__vote_data.author_id].is_implicit;
         __author_rep := __account_reputations[__vote_data.author_id].reputation;		  
      else
        select into __voter_rep, __implicit_voter_rep ha.reputation, ha.is_implicit 
        from __tmp_accounts ha where ha.id = __vote_data.voter_id;
        select into __author_rep, __implicit_author_rep ha.reputation, ha.is_implicit 
        from __tmp_accounts ha where ha.id = __vote_data.author_id;
      end if;
/*      IF __vote_data.author_id = __traced_author THEN
           raise notice 'Processing vote <%> rshares: %, prev_rshares: %', __vote_data.id, __vote_data.rshares, __vote_data.prev_rshares;
       select ha.name into __account_name from hive_accounts ha where ha.id = __vote_data.voter_id;
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

        IF _first_block_num IS NULL AND _last_block_num IS NULL THEN
          __account_reputations[__vote_data.author_id] := ROW(__vote_data.author_id, __new_author_rep, False, true)::AccountReputation;
        else
          update __tmp_accounts
          set reputation = __new_author_rep,
              is_implicit = False,
              changed = true
          where id = __vote_data.author_id;
        end if;
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

    IF _first_block_num IS NULL AND _last_block_num IS NULL THEN
      RETURN QUERY
        SELECT id, Reputation, is_implicit, changed
        FROM unnest(__account_reputations)
      WHERE Reputation IS NOT NULL and Changed 
      ;
    else
      return query select id, reputation, is_implicit, Changed
      from __tmp_accounts
      WHERE Reputation IS NOT NULL and Changed 
      ;
    end if;
END
$BODY$
;

ALTER FUNCTION public.calculate_account_reputations(integer, integer, character varying)
    OWNER TO syncad;

DROP FUNCTION IF EXISTS public.update_account_reputations;

CREATE OR REPLACE FUNCTION public.update_account_reputations(
  in _first_block_num INTEGER,
  in _last_block_num INTEGER)
  RETURNS VOID 
  LANGUAGE 'plpgsql'
  VOLATILE 
AS $BODY$
BEGIN
  UPDATE hive_accounts urs
  SET reputation = ds.reputation,
      is_implicit = ds.is_implicit
  FROM 
  (
    SELECT p.id as account_id, p.reputation, p.is_implicit
    FROM calculate_account_reputations(_first_block_num, _last_block_num) p
  ) ds
  WHERE urs.id = ds.account_id AND (urs.reputation != ds.reputation OR urs.is_implicit != ds.is_implicit)
  ;
END
$BODY$
;
