DROP TYPE IF EXISTS hivemind_app.database_api_vote CASCADE;

CREATE TYPE hivemind_app.database_api_vote AS (
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

DROP FUNCTION IF EXISTS hivemind_app.find_votes( character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION hivemind_app.find_votes
(
  in _AUTHOR hivemind_app.hive_accounts.name%TYPE,
  in _PERMLINK hivemind_app.hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF hivemind_app.database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE _POST_ID INT;
BEGIN
_POST_ID = hivemind_app.find_comment_id( _AUTHOR, _PERMLINK, True);

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
        hivemind_app.hive_votes_view v
    WHERE
        v.post_id = _POST_ID
    ORDER BY
        voter_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS hivemind_app.list_votes_by_voter_comment( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION hivemind_app.list_votes_by_voter_comment
(
  in _VOTER hivemind_app.hive_accounts.name%TYPE,
  in _AUTHOR hivemind_app.hive_accounts.name%TYPE,
  in _PERMLINK hivemind_app.hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF hivemind_app.database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE __voter_id INT;
DECLARE __post_id INT;
BEGIN

__voter_id = hivemind_app.find_account_id( _VOTER, True );
__post_id = hivemind_app.find_comment_id( _AUTHOR, _PERMLINK, True );

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
        hivemind_app.hive_votes_view v
    WHERE
        v.voter_id = __voter_id
        AND v.post_id >= __post_id
    ORDER BY
        v.post_id
    LIMIT _LIMIT
);

END
$function$;

DROP FUNCTION IF EXISTS hivemind_app.list_votes_by_comment_voter( character varying, character varying, character varying, int )
;
CREATE OR REPLACE FUNCTION hivemind_app.list_votes_by_comment_voter
(
  in _VOTER hivemind_app.hive_accounts.name%TYPE,
  in _AUTHOR hivemind_app.hive_accounts.name%TYPE,
  in _PERMLINK hivemind_app.hive_permlink_data.permlink%TYPE,
  in _LIMIT INT
)
RETURNS SETOF hivemind_app.database_api_vote
LANGUAGE 'plpgsql'
AS
$function$
DECLARE __voter_id INT;
DECLARE __post_id INT;
BEGIN

__voter_id = hivemind_app.find_account_id( _VOTER, True );
__post_id = hivemind_app.find_comment_id( _AUTHOR, _PERMLINK, True );

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
        hivemind_app.hive_votes_view v
    WHERE
        v.post_id = __post_id
        AND v.voter_id >= __voter_id
    ORDER BY
        v.voter_id
    LIMIT _LIMIT
);

END
$function$;
