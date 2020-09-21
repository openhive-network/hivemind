DROP TYPE IF EXISTS AccountReputation CASCADE;

CREATE TYPE AccountReputation AS (id int, reputation bigint, is_implicit boolean);

DROP FUNCTION IF EXISTS public.calculate_account_reputations();

CREATE OR REPLACE FUNCTION public.calculate_account_reputations(
  )
    RETURNS SETOF accountreputation 
    LANGUAGE 'plpgsql'

    COST 100
    VOLATILE 
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
  __rshares bigint;
  __prev_rshares bigint;
  __rep_delta bigint;
  __prev_rep_delta bigint;
  __traced_author int;
  __account_name varchar;
BEGIN
  __traced_author := 0; --42411; --16332;
  SELECT INTO __account_reputations ARRAY(SELECT ROW(a.id, 0, True)::AccountReputation
  FROM hive_accounts a
  WHERE a.id != 0
  ORDER BY a.id);

  FOR __vote_data IN
    SELECT rd.id, rd.author_id, rd.voter_id, rd.rshares,
      COALESCE((SELECT prd.rshares
                FROM hive_reputation_data prd
                WHERE prd.author_id = rd.author_id and prd.voter_id = rd.voter_id
                      and prd.permlink = rd.permlink and prd.id < rd.id
                        ORDER BY prd.id DESC LIMIT 1), 0) as prev_rshares
      FROM hive_reputation_data rd 
      ORDER BY rd.id
    LOOP
      __voter_rep := __account_reputations[__vote_data.voter_id - 1].reputation;
      __implicit_voter_rep := __account_reputations[__vote_data.voter_id - 1].is_implicit;
      __implicit_author_rep := __account_reputations[__vote_data.author_id - 1].is_implicit;
    
      IF __vote_data.author_id = __traced_author THEN
           raise notice 'Processing vote <%> rshares: %, prev_rshares: %', __vote_data.id, __vote_data.rshares, __vote_data.prev_rshares;
       select ha.name into __account_name from hive_accounts ha where ha.id = __vote_data.voter_id;
       raise notice 'Voter `%` (%) reputation: %', __account_name, __vote_data.voter_id,  __voter_rep;
      END IF;

      CONTINUE WHEN __voter_rep < 0;

      __author_rep := __account_reputations[__vote_data.author_id - 1].reputation;
      __rshares := __vote_data.rshares;
      __prev_rshares := __vote_data.prev_rshares;

      IF NOT __implicit_author_rep AND
       (__prev_rshares > 0 OR
         (__prev_rshares < 0 AND __voter_rep > __author_rep - __prev_rep_delta)) THEN
        __prev_rep_delta := (__prev_rshares >> 6)::bigint;
        __author_rep := __author_rep - __prev_rep_delta;
        __implicit_author_rep := __author_rep = 0;
        __account_reputations[__vote_data.author_id - 1] := ROW(__vote_data.author_id, __author_rep, __implicit_author_rep)::AccountReputation;
        IF __vote_data.author_id = __traced_author THEN
         raise notice 'Corrected author_rep by prev_rep_delta: % to have reputation: %', __prev_rep_delta, __author_rep;
        END IF;
      END IF;
    
      IF __rshares > 0 OR
         (__rshares < 0 AND NOT __implicit_voter_rep AND __voter_rep > __author_rep) THEN

        __rep_delta := (__rshares >> 6)::bigint;
        __new_author_rep = __author_rep + __rep_delta;
        __account_reputations[__vote_data.author_id - 1] := ROW(__vote_data.author_id, __new_author_rep, False)::AccountReputation;
        IF __vote_data.author_id = __traced_author THEN
          raise notice 'Changing account: <%> reputation from % to %', __vote_data.author_id, __author_rep, __new_author_rep;
        END IF;
      ELSE
        IF __vote_data.author_id = __traced_author THEN
            raise notice 'Ignoring reputation change due to unmet conditions... Author_rep: %, Voter_rep: %', __author_rep, __voter_rep;
        END IF;
      END IF;
    END LOOP;

    RETURN QUERY
      SELECT id, Reputation, is_implicit
      FROM unnest(__account_reputations);
END
$BODY$;
