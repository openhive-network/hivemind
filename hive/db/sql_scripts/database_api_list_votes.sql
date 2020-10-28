DROP TYPE IF EXISTS database_api_vote CASCADE;

CREATE TYPE database_api_vote AS (
  id BIGINT,
  voter VARCHAR(16),
  author VARCHAR(16),
  permlink VARCHAR(255),
  weight NUMERIC,
  rshares BIGINT,
  percent INT,
  last_update TIMESTAMP,
  num_changes INT,
  reputation BIGINT
);

DROP FUNCTION IF EXISTS find_votes( character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.find_votes
(
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE _POST_ID INT;
BEGIN
_POST_ID = find_comment_id( _AUTHOR, _PERMLINK, True);

RETURN QUERY
(
    SELECT
        v.id,
        v.voter,
        v.author,
        v.permlink,
        v.weight,
        v.rshares,
        v.percent,
        v.last_update,
        v.num_changes,
        v.reputation
    FROM
        hive_votes_view v
    WHERE
        v.post_id = _POST_ID
    ORDER BY
        voter_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS list_votes_by_voter_comment( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.list_votes_by_voter_comment
(
  in _VOTER hive_accounts.name%TYPE,
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE __voter_id INT;
DECLARE __post_id INT;
BEGIN

__voter_id = find_account_id( _VOTER, True );
__post_id = find_comment_id( _AUTHOR, _PERMLINK, True );

RETURN QUERY
(
    SELECT
        v.id,
        v.voter,
        v.author,
        v.permlink,
        v.weight,
        v.rshares,
        v.percent,
        v.last_update,
        v.num_changes,
        v.reputation
    FROM
        hive_votes_view v
    WHERE
        v.voter_id = __voter_id
        AND v.post_id >= __post_id
    ORDER BY
        v.post_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS list_votes_by_comment_voter( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION public.list_votes_by_comment_voter
(
  in _VOTER hive_accounts.name%TYPE,
  in _AUTHOR hive_accounts.name%TYPE,
  in _PERMLINK hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE __voter_id INT;
DECLARE __post_id INT;
BEGIN

__voter_id = find_account_id( _VOTER, _VOTER != '' ); -- voter is optional
__post_id = find_comment_id( _AUTHOR, _PERMLINK, True );

RETURN QUERY
(
    SELECT
        v.id,
        v.voter,
        v.author,
        v.permlink,
        v.weight,
        v.rshares,
        v.percent,
        v.last_update,
        v.num_changes,
        v.reputation
    FROM
        hive_votes_view v
    WHERE
        v.post_id = __post_id
        AND v.voter_id >= __voter_id
    ORDER BY
        v.voter_id
    LIMIT _LIMIT
);

END
$function$;
