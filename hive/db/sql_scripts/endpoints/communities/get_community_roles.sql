/** openapi:paths
/communities/{name}/roles:
  get:
    tags:
      - blog_api
    summary: Get a community''s roles
    description: |
      Returns the community''s accounts that have a role other than guest, highest role first, the same list as `bridge.list_community_roles`.
      Each row is `[account, role, title]`.

      To fetch the next page pass the account name of the last row of the previous page as `last`.

      SQL example
      * `SELECT hivemind_endpoints.get_community_roles(''hive-123456'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/communities/hive-123456/roles?page-size=50''`
    operationId: hivemind_endpoints.get_community_roles
    parameters:
      - in: path
        name: name
        required: true
        schema:
          type: string
        description: Name of the community (`hive-NNNNNN`)
      - in: query
        name: page-size
        required: false
        schema:
          type: integer
          default: NULL
        description: Maximum number of rows to return, at most 1000; the default is 50
      - in: query
        name: last
        required: false
        schema:
          type: string
          default: NULL
        description: Account of the last row of the previous page
    responses:
      '200':
        description: |
          Get a community''s roles

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_string_tuple'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown community or last account, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_community_roles;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_community_roles(
    "name" TEXT,
    "page-size" INT = NULL,
    "last" TEXT = NULL
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('bridge', 'list_community_roles',
    jsonb_build_object('community', "name", 'limit', "page-size", 'last', "last"));
END
$$;
