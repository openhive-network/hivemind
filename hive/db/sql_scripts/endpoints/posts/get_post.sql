/** openapi:paths
/posts/{author}/{permlink}:
  get:
    tags:
      - blog_api
    summary: Get a post
    description: |
      Returns one post or comment, the same object as `bridge.get_post`.

      SQL example
      * `SELECT hivemind_endpoints.get_post(''alice'', ''my-awesome-post'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post''`
    operationId: hivemind_endpoints.get_post
    parameters:
      - in: path
        name: author
        required: true
        schema:
          type: string
        description: Author of the post
      - in: path
        name: permlink
        required: true
        schema:
          type: string
        description: Permlink of the post
      - in: query
        name: observer
        required: false
        schema:
          type: string
          default: NULL
        description: |
          Account whose mutes and blacklists are applied. The response without an observer
          is the one meant for caching.
    responses:
      '200':
        description: |
          The post

          * Returns `JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.bridge_post'
              x-sql-datatype: JSONB
      '400':
        description: Unknown or deleted post, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_post;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_post(
    "author" TEXT,
    "permlink" TEXT,
    "observer" TEXT = NULL
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'get_post',
    jsonb_build_object('author', "author", 'permlink', "permlink", 'observer', "observer"));
END
$$;
