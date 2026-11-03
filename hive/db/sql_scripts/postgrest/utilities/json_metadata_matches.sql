-- True when _metadata parses as JSON and the value at _path equals one of _values (jsonb equality,
-- so a number matches numerically). Metadata that is not valid JSON never matches.
-- _literal, when set, is text every matching document must contain unless it holds an escape
-- sequence; it skips parsing most rows. Pass NULL when a match may be spelled differently
-- (a number: 1e2 equals 100).
-- A STABLE SQL function (pg_input_is_valid is STABLE) so that the planner inlines it; CASE keeps
-- the cast behind the validity check.
DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.json_metadata_matches;
CREATE FUNCTION hivemind_postgrest_utilities.json_metadata_matches(IN _metadata TEXT, IN _path TEXT[], IN _values JSONB[], IN _literal TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS
$$
  SELECT CASE
    WHEN (_literal IS NULL OR strpos(_metadata, _literal) > 0 OR strpos(_metadata, '\') > 0)
         AND pg_input_is_valid(_metadata, 'jsonb')
    THEN COALESCE(_metadata::jsonb #> _path = ANY(_values), FALSE)
    ELSE FALSE
  END
$$
;
