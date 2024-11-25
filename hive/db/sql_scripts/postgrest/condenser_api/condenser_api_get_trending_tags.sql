DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_trending_tags;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_trending_tags(IN _json_is_object BOOLEAN, IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
_start_tag TEXT;
_limit INT;
_category_id INT;
_payout_limit hivemind_app.hive_posts.payout%TYPE;
_result JSONB;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"start_tag","limit"}', '{"string","number"}', 0);
  _start_tag = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'start_tag', 0, False);
  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 1, False);
  _start_tag = hivemind_postgrest_utilities.valid_tag(_start_tag, True);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 250, 1, 250, 'limit');
  _category_id = hivemind_postgrest_utilities.find_category_id( _start_tag, True );

  IF _category_id <> 0 THEN
    SELECT SUM(hp.payout + hp.pending_payout) INTO _payout_limit
    FROM hivemind_app.hive_posts hp
    WHERE hp.category_id = _category_id AND hp.counter_deleted = 0 AND NOT hp.is_paidout;
  END IF;

_result = (
  SELECT jsonb_agg(to_jsonb(row)) FROM (
    WITH row AS (
      SELECT
        hcd.category AS name,
        COUNT(*) AS comments,
        SUM(CASE WHEN hp.depth = 0 THEN 1 ELSE 0 END) AS top_posts,
        SUM(hp.payout + hp.pending_payout) || ' HBD' AS total_payouts
      FROM
        hivemind_app.hive_posts hp
        JOIN hivemind_app.hive_category_data hcd ON hcd.id = hp.category_id
      WHERE NOT hp.is_paidout AND hp.counter_deleted = 0
      GROUP BY hcd.category
      HAVING _category_id = 0 OR SUM(hp.payout + hp.pending_payout) < _payout_limit OR ( SUM(hp.payout + hp.pending_payout) = _payout_limit AND hcd.category > _start_tag )
      ORDER BY SUM(hp.payout + hp.pending_payout) DESC, hcd.category ASC
      LIMIT _limit
    )
    SELECT name, comments - top_posts AS comments, top_posts, total_payouts FROM row LIMIT _limit
  ) row
);

  RETURN COALESCE(_result, '[]'::jsonb);
END;
$$
;