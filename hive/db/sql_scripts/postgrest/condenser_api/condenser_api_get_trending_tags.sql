DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_trending_tags;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_trending_tags(IN _params JSONB)
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
  _params = hivemind_postgrest_utilities.validate_json_arguments(_params, '{"start_tag": "string", "limit": "number"}', 0, NULL);
  _start_tag = hivemind_postgrest_utilities.parse_argument_from_json(_params, 'start_tag', False);
  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
  _start_tag = hivemind_postgrest_utilities.valid_tag(_start_tag, True);
  _limit = hivemind_postgrest_utilities.valid_number(_limit, 250, 1, 250, 'limit');
  _category_id = hivemind_postgrest_utilities.find_category_id( _start_tag, True );

  IF _category_id <> 0 THEN
    SELECT SUM(hp.payout + hp.pending_payout) INTO _payout_limit
    FROM hivemind_app.hive_posts hp
    WHERE hp.category_id = _category_id AND hp.counter_deleted = 0 AND NOT hp.is_paidout;
  END IF;

_result = (
  SELECT jsonb_agg(to_jsonb(row)) FROM ( -- condenser_api_get_trending_tags
    -- Aggregate by id first and resolve only the surviving ids' names by primary key: a join on the posts
    -- would hash the whole category table. Names are unique, so grouping by id groups as by name.
    WITH totals AS (
      SELECT
        hp.category_id,
        COUNT(*) AS comments,
        SUM(CASE WHEN hp.depth = 0 THEN 1 ELSE 0 END) AS top_posts,
        SUM(hp.payout + hp.pending_payout) AS total
      FROM hivemind_app.hive_posts hp
      WHERE NOT hp.is_paidout AND hp.counter_deleted = 0
      GROUP BY hp.category_id
    ),
    named AS MATERIALIZED (
      SELECT
        (SELECT hcd.category FROM hivemind_app.hive_category_data hcd WHERE hcd.id = t.category_id) AS name,
        t.comments,
        t.top_posts,
        t.total
      FROM totals t
      WHERE _category_id = 0 OR t.total <= _payout_limit
    ),
    row AS (
      SELECT
        n.name,
        n.comments,
        n.top_posts,
        n.total || ' HBD' AS total_payouts
      FROM named n
      WHERE n.name IS NOT NULL
        AND ( _category_id = 0 OR n.total < _payout_limit OR ( n.total = _payout_limit AND n.name > _start_tag ) )
      ORDER BY n.total DESC, n.name ASC
      LIMIT _limit
    )
    SELECT name, comments - top_posts AS comments, top_posts, total_payouts FROM row LIMIT _limit
  ) row
);

  RETURN COALESCE(_result, '[]'::jsonb);
END;
$$
;