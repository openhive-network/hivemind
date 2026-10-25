/** openapi:paths
/posts/{author}/{permlink}/header:
  get:
    tags:
      - blog_api
    summary: Get a post''s header
    description: |
      Returns the author, permlink, category and depth of a post or comment, the same object as
      `bridge.get_post_header`.

      SQL example
      * `SELECT hivemind_endpoints.get_post_header(''alice'', ''my-awesome-post'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/header''`
    operationId: hivemind_endpoints.get_post_header
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
    responses:
      '200':
        description: |
          The post''s header

          * Returns `JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.post_header'
              x-sql-datatype: JSONB
      '400':
        description: Unknown or deleted post, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_post_header;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_post_header(
    "author" TEXT,
    "permlink" TEXT
)
RETURNS JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN hivemind_postgrest_utilities.rest_json_rpc_call('bridge', 'get_post_header',
    jsonb_build_object('author', "author", 'permlink', "permlink"));
END
$$;
