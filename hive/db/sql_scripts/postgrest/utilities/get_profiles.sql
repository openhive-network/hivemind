DROP FUNCTION IF EXISTS hivemind_postgrest_utilities.get_profiles;
CREATE OR REPLACE FUNCTION hivemind_postgrest_utilities.get_profiles(IN   _accounts JSONB, IN  _observer TEXT)
RETURNS JSONB
LANGUAGE 'plpgsql' STABLE
AS
$function$
DECLARE
  _account_names TEXT[];
  _observer_id INT;
  _result JSONB;
  _found_accounts_amount INT;
  _accounts_amount INT;
  _found_accounts TEXT[];
  _missing_accounts JSONB;
BEGIN

    _accounts_amount = jsonb_array_length(_accounts);
    IF _accounts_amount > 1000 THEN
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception('accounts amount is greather than max allowed (1000)');
    END IF;

    SELECT array_agg(value) INTO _account_names FROM jsonb_array_elements_text(_accounts);
    _account_names = hivemind_postgrest_utilities.valid_accounts(_account_names, false);

    _observer_id = hivemind_postgrest_utilities.find_account_id(
            hivemind_postgrest_utilities.valid_account(_observer, True),
            True);

    SELECT jsonb_agg(jsonb_build_object(
            'id', row.id,
            'name', row.name,
            'created', hivemind_postgrest_utilities.json_date(row.created_at),
            'active', hivemind_postgrest_utilities.json_date(row.active_at),
            'post_count', row.post_count,
            'reputation', hivemind_postgrest_utilities.rep_log10(row.reputation),
            'blacklists', to_jsonb('{}'::INT[]),
            'stats', jsonb_build_object('rank', row.rank, 'following', row.following, 'followers', row.followers),
            'json_metadata', row.json_metadata,
            'posting_json_metadata', row.posting_json_metadata
        )) FROM (SELECT * FROM hivemind_app.hive_accounts_info_view WHERE name = ANY(_account_names)) row INTO _result;


    SELECT array_agg(value#>>'{name}') INTO _found_accounts FROM jsonb_array_elements(_result);
    _found_accounts_amount = array_length(_found_accounts, 1);

    IF _accounts_amount <> _found_accounts_amount OR _found_accounts_amount IS NULL THEN
        IF _found_accounts_amount = 0 OR _found_accounts_amount IS NULL THEN
            SELECT jsonb_agg(jsonb_build_object(name, 'account does not exist'))
            INTO _missing_accounts
            FROM unnest(_account_names) name;
        ELSE
            SELECT array_agg(value#>>'{name}') INTO _found_accounts FROM jsonb_array_elements(_result);
            SELECT jsonb_agg(jsonb_build_object(name, 'account does not exist'))
            INTO _missing_accounts
            FROM (SELECT unnest(_account_names) as name EXCEPT SELECT unnest(_found_accounts)) missing;
        END IF;
        RAISE EXCEPTION '%', hivemind_postgrest_utilities.raise_parameter_validation_exception(_missing_accounts::text);
    END IF;

    IF _observer_id IS NOT NULL AND _observer_id <> 0 THEN
        SELECT jsonb_agg(
                       jsonb_set(
                               account_row,
                               '{context}',
                               COALESCE(
                                       (SELECT
                                            CASE
                                                WHEN state = 2 THEN
                                                    jsonb_build_object('followed', false, 'muted', true)
                                                WHEN state = 1 THEN
                                                    jsonb_build_object('followed', true)
                                                ELSE
                                                    jsonb_build_object('followed', false)
                                                END
                                        FROM hivemind_app.hive_follows
                                        WHERE follower = _observer_id
                                          AND following = (account_row->>'id')::INT),
                                       jsonb_build_object('followed', false)
                                   )
                           )
                   )
        FROM jsonb_array_elements(_result) account_row
        INTO _result;
    END IF;


    SELECT jsonb_agg(
                   jsonb_set(
                               account_row - 'json_metadata' - 'posting_json_metadata',
                               '{metadata}',
                               hivemind_postgrest_utilities.extract_profile_metadata(
                                           account_row->>'json_metadata',
                                           account_row->>'posting_json_metadata'
                                   )
                       )
               )
    FROM jsonb_array_elements(_result) account_row INTO _result;

    RETURN _result;
END
$function$
;