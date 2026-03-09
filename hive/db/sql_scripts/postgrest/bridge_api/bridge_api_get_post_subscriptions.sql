-- API endpoint: bridge.get_post_subscriptions
-- Returns a list of posts/comments that the given account has subscribed to

DROP FUNCTION IF EXISTS hivemind_endpoints.bridge_api_get_post_subscriptions;
CREATE FUNCTION hivemind_endpoints.bridge_api_get_post_subscriptions(IN _params JSONB)
RETURNS JSONB
LANGUAGE 'plpgsql'
STABLE
AS
$$
DECLARE
    _account_id INT;
    _limit INT;
    _offset INT;
    _result JSONB;
BEGIN
    _params = hivemind_postgrest_utilities.validate_json_arguments(
        _params,
        '{"account": "string", "limit": "number", "offset": "number"}',
        1,
        NULL
    );

    _account_id = hivemind_postgrest_utilities.find_account_id(
        hivemind_postgrest_utilities.valid_account(
            hivemind_postgrest_utilities.parse_argument_from_json(_params, 'account', True),
            False
        ),
        True
    );

    _limit = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'limit', False);
    _limit = hivemind_postgrest_utilities.valid_number(_limit, 100, 1, 100, 'limit');

    _offset = hivemind_postgrest_utilities.parse_integer_argument_from_json(_params, 'offset', False);
    _offset = COALESCE(_offset, 0);

    _result = (
        SELECT jsonb_agg(row_data) FROM (
            SELECT jsonb_build_object(
                'author', ha.name,
                'permlink', hpd.permlink,
                'title', COALESCE(hpdata.title, ''),
                'depth', hp.depth,
                'subscribed_at', hps.created_at
            ) AS row_data
            FROM hivemind_app.hive_post_subscriptions hps
            JOIN hivemind_app.hive_posts hp ON hps.post_id = hp.id
            JOIN hivemind_app.hive_accounts ha ON hp.author_id = ha.id
            JOIN hivemind_app.hive_permlink_data hpd ON hp.permlink_id = hpd.id
            LEFT JOIN hivemind_app.hive_post_data hpdata ON hp.id = hpdata.id
            WHERE hps.account_id = _account_id
              AND hp.counter_deleted = 0
            ORDER BY hps.created_at DESC
            LIMIT _limit
            OFFSET _offset
        ) sub
    );

    RETURN COALESCE(_result, '[]'::jsonb);
END
$$;
