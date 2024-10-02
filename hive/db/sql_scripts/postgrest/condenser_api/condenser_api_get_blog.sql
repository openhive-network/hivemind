DROP FUNCTION IF EXISTS hivemind_endpoints.condenser_api_get_blog;
CREATE FUNCTION hivemind_endpoints.condenser_api_get_blog(IN _json_is_object BOOLEAN, IN _params JSON, IN _get_entries BOOLEAN)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
  _account TEXT;
  _offset INT;
  _limit INT;

  _account_id INT;
  _result JSONB;
BEGIN
  PERFORM hivemind_postgrest_utilities.validate_json_parameters(_json_is_object, _params, '{"account", "start_entry_id", "limit"}', '{"string", "number", "number"}', 1);
  _account = hivemind_postgrest_utilities.parse_string_argument_from_json(_params, _json_is_object, 'account', 0, True);
  _offset = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'start_entry_id', 1, False);
  _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, _json_is_object, 'limit', 2, False);

  _account = hivemind_postgrest_utilities.valid_account(_account, False);

  IF _offset IS NULL OR _offset = 0 THEN
    _offset = -1;
  END IF;

  _offset = hivemind_postgrest_utilities.valid_offset(_offset);

  IF _limit IS NULL OR _limit = 0 THEN
    _limit = GREATEST(_offset + 1, 1);
    _limit = LEAST(_limit, 500);
  END IF;

  _limit = hivemind_postgrest_utilities.valid_number(_limit, NULL, 1, 500, 'limit');
  _account_id = hivemind_postgrest_utilities.find_account_id(_account, True);

  IF _offset < 0 THEN
    _offset = ( SELECT COUNT(1) - 1 FROM hivemind_app.hive_feed_cache hfc WHERE hfc.account_id = _account_id );
    
    _offset = _offset - _limit + 1;
    IF _offset < 0 THEN
      _offset = 0;
    END IF;
  ELSEIF _offset + 1 < _limit THEN
    _offset = 0;
    _limit = _offset + 1;
  ELSE
    _offset = _offset - _limit + 1;
  END IF;

  IF _get_entries THEN
    RETURN (
      SELECT to_json(result.array) FROM (
        SELECT ARRAY (
          SELECT json_build_object(
            'blog', _account,
            'entry_id', row.entry_id,
            'author', row.author,
            'permlink', row.permlink,
            'reblogged_on', hivemind_postgrest_utilities.json_date(row.reblogged_at)
          ) FROM (
            SELECT
              blog.entry_id::INT,
              ha.name as author,
              hpd.permlink,
              (
                CASE hp.author_id = _account_id
                WHEN True THEN '1970-01-01T00:00:00'::timestamp
                ELSE blog.created_at
                END
              ) AS reblogged_at
            FROM
            (
              SELECT
                hfc.created_at, hfc.post_id, row_number() over (ORDER BY hfc.created_at ASC, hfc.post_id ASC) - 1 as entry_id
              FROM
                hivemind_app.hive_feed_cache hfc
              WHERE
                hfc.account_id = _account_id
              ORDER BY hfc.created_at ASC, hfc.post_id ASC
              LIMIT _limit
              OFFSET _offset
            ) as blog
            JOIN hivemind_app.hive_posts hp ON hp.id = blog.post_id
            JOIN hivemind_app.hive_accounts ha ON ha.id = hp.author_id
            JOIN hivemind_app.hive_permlink_data hpd ON hpd.id = hp.permlink_id
            ORDER BY blog.created_at DESC, blog.post_id DESC
          ) row
        )
      ) result
    );
  ELSE
    RETURN (
      SELECT to_json(result.array) FROM (
        SELECT ARRAY (
          SELECT json_build_object(
            'blog', _account,
            'entry_id', row.entry_id,
            'comment', hivemind_postgrest_utilities.create_condenser_post_object(row, 0, False),
            'reblogged_on', row.reblogged_at)  FROM (
            SELECT
              hp.id,
              blog.entry_id::INT,
              hp.author,
              hp.permlink,
              hp.author_rep,
              hp.title,
              hp.body,
              hp.category,
              hp.depth,
              hp.promoted,
              hp.payout,
              hp.pending_payout,
              hp.payout_at,
              hp.is_paidout,
              hp.children,
              hp.created_at,
              hp.updated_at,
              (
                CASE hp.author_id = _account_id
                  WHEN True THEN '1970-01-01T00:00:00'::timestamp
                  ELSE blog.created_at
                END
              ) as reblogged_at,
              hp.rshares,
              hp.json,
              hp.parent_author,
              hp.parent_permlink_or_category,
              hp.curator_payout_value,
              hp.max_accepted_payout,
              hp.percent_hbd,
              hp.beneficiaries,
              hp.url,
              hp.root_title,
              hp.author_rewards
            FROM
            (
              SELECT
                hfc.created_at, hfc.post_id, row_number() over (ORDER BY hfc.created_at ASC, hfc.post_id ASC) - 1 as entry_id
              FROM
                hivemind_app.hive_feed_cache hfc
              WHERE
                hfc.account_id = _account_id
              ORDER BY hfc.created_at ASC, hfc.post_id ASC
              LIMIT _limit
              OFFSET _offset
            ) as blog,
            LATERAL hivemind_app.get_post_view_by_id(blog.post_id) hp
            -- in python code order was ASC, but because we append new elements to array in reverse order, order is DESC here
            ORDER BY blog.created_at DESC, blog.post_id DESC
          ) row      
        )
      ) result
    );
  END IF;

END;
$$
;