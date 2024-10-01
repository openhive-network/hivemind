DROP TYPE IF EXISTS hivemind_postgrest_utilities.vote_arguments CASCADE;
CREATE TYPE hivemind_postgrest_utilities.vote_arguments AS (
  author TEXT,
  permlink TEXT
);

DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_validated_vote_arguments;
CREATE FUNCTION hivemind_postgrest_utilities.get_validated_vote_arguments(
  _params JSON,
  _json_is_object BOOLEAN
) RETURNS hivemind_postgrest_utilities.vote_arguments AS $$
DECLARE
  _vote_args hivemind_postgrest_utilities.vote_arguments;
BEGIN
  _vote_args.author := hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'author', 0, True);
  _vote_args.author := hivemind_postgrest_utilities.valid_account(_vote_args.author, False);

  _vote_args.permlink := hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'permlink', 1, True);
  _vote_args.permlink := hivemind_postgrest_utilities.valid_permlink(_vote_args.permlink, False);

  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"author","permlink"}', '{"string","string"}');

  RETURN _vote_args;
END;
$$ LANGUAGE plpgsql;