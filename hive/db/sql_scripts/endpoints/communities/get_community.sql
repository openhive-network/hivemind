/** openapi:paths
/communities/{name}:
  get:
    tags:
      - blog_api
    summary: Get a community
    description: |
      Returns the community, the same object as `bridge.get_community`.

      SQL example
      * `SELECT hivemind_endpoints.get_community(''hive-123456'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/communities/hive-123456''`
    operationId: hivemind_endpoints.get_community
    parameters:
      - in: path
        name: name
        required: true
        schema:
          type: string
        description: Name of the community (`hive-NNNNNN`)
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Account whose subscription and role is reported in `context`. The response
          without an observer is the one meant for caching.
    responses:
      '200':
        description: |
          The community

          * Returns `JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.bridge_community'
              x-sql-datatype: JSONB
      '400':
        description: Unknown community or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_community;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_community(
    "name" TEXT,
    "observer" TEXT = NULL
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'get_community',
    jsonb_build_object('name', "name", 'observer', "observer"));
END
$$;
