/** openapi:paths
/accounts/{account-name}/relationships:
  get:
    tags:
      - blog_api
    summary: Get the relationship of an account to each of a list of accounts
    description: |
      Returns, for each listed account, whether the account follows, ignores (mutes) or blacklists it,
      and whether the account follows its blacklist or its mute list, the same fields as
      `bridge.get_relationship_between_accounts`. One row is returned per distinct listed account,
      in the order they are listed.

      SQL example
      * `SELECT * FROM hivemind_endpoints.get_account_relationships(''alice'', ''bob,carol'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/accounts/alice/relationships?accounts=bob,carol''`
    operationId: hivemind_endpoints.get_account_relationships
    parameters:
      - in: path
        name: account-name
        required: true
        schema:
          type: string
        description: Account whose relationships are returned
      - in: query
        name: accounts
        required: true
        schema:
          type: string
        description: Comma-separated list of at most 100 account names
    responses:
      '200':
        description: |
          Relationship of the account to each listed account

          * Returns `SETOF hivemind_endpoints.account_relationship`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_account_relationship'
            example: [
              {
                "account": "bob",
                "follows": true,
                "ignores": false,
                "blacklists": false,
                "follows_blacklists": false,
                "follows_muted": false
              }
            ]
      '400':
        description: Unknown account, missing or invalid account list, or more than 100 listed accounts
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_account_relationships;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_account_relationships(
    "account-name" TEXT,
    "accounts" TEXT
)
RETURNS SETOF hivemind_endpoints.account_relationship 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
DECLARE
  _max_accounts CONSTANT INT := 100;
  _account_id INT;
  _names TEXT[];
  _unknown TEXT;
BEGIN
  _account_id = hivemind_postgrest_utilities.find_account_id(
    hivemind_postgrest_utilities.valid_account("account-name", False),
    False);
  IF _account_id = 0 THEN
    RAISE EXCEPTION 'Account ''%'' does not exist', "account-name";
  END IF;

  IF "accounts" IS NULL OR btrim("accounts") = '' THEN
    RAISE EXCEPTION 'accounts is required for this endpoint';
  END IF;

  _names = ARRAY(SELECT btrim(n) FROM unnest(string_to_array("accounts", ',')) AS n);

  IF cardinality(_names) > _max_accounts THEN
    RAISE EXCEPTION 'accounts may list at most % names, got %', _max_accounts, cardinality(_names);
  END IF;

  PERFORM hivemind_postgrest_utilities.valid_accounts(_names);

  SELECT n.name INTO _unknown
  FROM unnest(_names) WITH ORDINALITY AS n(name, ord)
  WHERE NOT EXISTS (SELECT 1 FROM hivemind_app.hive_accounts ha WHERE ha.name = n.name)
  ORDER BY n.ord
  LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Account ''%'' does not exist', _unknown;
  END IF;

  RETURN QUERY
    SELECT
      listed.name,
      r.follows,
      r.ignores,
      r.blacklists,
      r.follows_blacklists,
      r.follows_muted
    FROM (
      SELECT n.name, MIN(n.ord) AS ord
      FROM unnest(_names) WITH ORDINALITY AS n(name, ord)
      GROUP BY n.name
    ) listed
    JOIN hivemind_app.hive_accounts ha ON ha.name = listed.name
    CROSS JOIN LATERAL hivemind_postgrest_utilities.get_relationship_between_accounts(_account_id, ha.id) r
    ORDER BY listed.ord;
END
$$;
