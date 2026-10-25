/** openapi:paths
/posts/{author}/{permlink}/reblogged-by:
  get:
    tags:
      - blog_api
    summary: Get the accounts that reblogged a post
    description: |
      Returns the accounts that reblogged the post, the same list as `condenser_api.get_reblogged_by`,
      in alphabetical order.

      SQL example
      * `SELECT hivemind_endpoints.get_post_reblogged_by(''alice'', ''my-awesome-post'');`

      REST call example
      * `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/reblogged-by''`
    operationId: hivemind_endpoints.get_post_reblogged_by
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
          Accounts that reblogged the post

          * Returns `SETOF JSONB`
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/hivemind_endpoints.array_of_string'
              x-sql-datatype: SETOF JSONB
      '400':
        description: Unknown post, or an invalid parameter
 */
-- openapi-generated-code-begin
DROP FUNCTION IF EXISTS hivemind_endpoints.get_post_reblogged_by;
CREATE OR REPLACE FUNCTION hivemind_endpoints.get_post_reblogged_by(
    "author" TEXT,
    "permlink" TEXT
)
RETURNS SETOF JSONB 
-- openapi-generated-code-end
LANGUAGE 'plpgsql' STABLE
AS
$$
BEGIN
  RETURN QUERY SELECT * FROM hivemind_postgrest_utilities.rest_json_rpc_rows('condenser_api', 'get_reblogged_by',
    jsonb_build_object('author', "author", 'permlink', "permlink"));
END
$$;
