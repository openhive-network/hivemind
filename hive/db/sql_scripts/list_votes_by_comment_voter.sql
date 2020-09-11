DROP FUNCTION IF EXISTS list_votes_by_comment_voter( character varying, character varying, character varying, int );

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
DECLARE _VOTER_ID INT;
DECLARE _POST_ID INT;
BEGIN

_VOTER_ID = get_account( _VOTER, true );
_POST_ID = find_comment_id( _AUTHOR, _PERMLINK, True);

RETURN QUERY
(
        SELECT
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
                ( v.post_id = _POST_ID and v.voter_id >= _VOTER_ID )
                OR
                ( v.post_id > _POST_ID )
            ORDER BY
              post_id,
              voter_id
        LIMIT _LIMIT
);

END
$function$;