/** openapi:components:schemas
hivemind_endpoints.block_range_type:
  type: object
  properties:
    from:
      type: integer
    to:
      type: integer
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.block_range_type CASCADE;
CREATE TYPE hivemind_endpoints.block_range_type AS (
    "from" INT,
    "to" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.operation_body:
  type: object
  x-sql-datatype: JSON
  properties:
    type:
      type: string
    value:
      type: object
*/

/** openapi:components:schemas
hivemind_endpoints.array_of_operations:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.operation_body'
*/

/** openapi:components:schemas
hivemind_endpoints.operation:
  type: object
  properties:
    op:
      $ref: '#/components/schemas/hivemind_endpoints.operation_body'
      x-sql-datatype: JSONB
      description: operation body
    block:
      type: integer
      description: block containing the operation
    trx_id:
      type: ["string", "null"]
      description: hash of the transaction
    op_pos:
      type: integer
      description: >-
        operation identifier that indicates its sequence number in transaction
    op_type_id:
      type: integer
      description: operation type identifier
    timestamp:
      type: string
      format: date-time
      description: creation date
    virtual_op:
      type: boolean
      description: true if is a virtual operation
    operation_id:
      type: string
      description: >-
        unique operation identifier with
        an encoded block number and operation type id
    trx_in_block:
      type: integer
      x-sql-datatype: SMALLINT
      description: >-
        transaction identifier that indicates its sequence number in block
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.operation CASCADE;
CREATE TYPE hivemind_endpoints.operation AS (
    "op" JSONB,
    "block" INT,
    "trx_id" TEXT,
    "op_pos" INT,
    "op_type_id" INT,
    "timestamp" TIMESTAMP,
    "virtual_op" BOOLEAN,
    "operation_id" TEXT,
    "trx_in_block" SMALLINT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.operation_history:
  type: object
  properties:
    total_operations:
      type: integer
      description: Total number of operations
    total_pages:
      type: integer
      description: Total number of pages
    block_range:
      $ref: '#/components/schemas/hivemind_endpoints.block_range_type'
      description: Range of blocks that contains the returned pages  
    operations_result:
      type: array
      items:
        $ref: '#/components/schemas/hivemind_endpoints.operation'
      description: List of operation results
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.operation_history CASCADE;
CREATE TYPE hivemind_endpoints.operation_history AS (
    "total_operations" INT,
    "total_pages" INT,
    "block_range" hivemind_endpoints.block_range_type,
    "operations_result" hivemind_endpoints.operation[]
);
-- openapi-generated-code-end

-- Note: the SQL composite type `hivemind_endpoints.reblog_status` is
-- defined in postgrest/utilities/get_reblogged_posts.sql (not here) to
-- avoid CASCADE DROP destroying the utility functions that depend on it.
-- The OpenAPI schema fragments below are required so $ref lookups in
-- the regenerator resolve, but `process_openapi.py` would otherwise
-- emit a duplicate `DROP TYPE ... CASCADE; CREATE TYPE reblog_status`
-- block right after the YAML. That block MUST be hand-removed after
-- every run of `scripts/openapi_rewrite.sh` until the regenerator
-- gains an `x-skip-create-type`-style override.

/** openapi:components:schemas
hivemind_endpoints.reblog_status:
  type: object
  properties:
    author:
      type: string
      description: Post author account name
    permlink:
      type: string
      description: Post permlink
    reblogged:
      type: boolean
      description: True if the observer has reblogged this post
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_reblog_status:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.reblog_status'
 */

/** openapi:components:schemas
hivemind_endpoints.hbd_asset:
  type: object
  x-sql-datatype: JSON
  properties:
    amount:
      type: string
      description: HBD amount in raw integer units (multiply by 10^-precision to get HBD)
    precision:
      type: integer
      description: Decimal precision of the amount (always 3 for HBD)
    nai:
      type: string
      description: Numeric Asset Identifier (''@@000000013'' for HBD)
 */

/** openapi:components:schemas
hivemind_endpoints.pending_author_rewards:
  type: object
  properties:
    account:
      type: string
      description: Account name
    pending_post_count:
      type: integer
      description: Number of posts awaiting payout
    gross_pending_payout:
      $ref: '#/components/schemas/hivemind_endpoints.hbd_asset'
      x-sql-datatype: JSON
      description: Sum of pending payouts across all unpaid posts (capped by max_accepted_payout); equals author + beneficiaries + curators
    estimated_author_payout:
      $ref: '#/components/schemas/hivemind_endpoints.hbd_asset'
      x-sql-datatype: JSON
      description: Estimated portion of gross payout going to the author
    estimated_beneficiaries_payout:
      $ref: '#/components/schemas/hivemind_endpoints.hbd_asset'
      x-sql-datatype: JSON
      description: Estimated portion of gross payout going to beneficiaries
    estimated_curators_payout:
      $ref: '#/components/schemas/hivemind_endpoints.hbd_asset'
      x-sql-datatype: JSON
      description: Estimated portion of gross payout going to curators (0 if allow_curation_rewards is false)
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.pending_author_rewards CASCADE;
CREATE TYPE hivemind_endpoints.pending_author_rewards AS (
    "account" TEXT,
    "pending_post_count" INT,
    "gross_pending_payout" JSON,
    "estimated_author_payout" JSON,
    "estimated_beneficiaries_payout" JSON,
    "estimated_curators_payout" JSON
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.pending_curation_rewards:
  type: object
  properties:
    account:
      type: string
      description: Account name
    pending_vote_count:
      type: integer
      description: Number of recent votes awaiting payout (within the last 8 chain-days)
    estimated_curation_payout:
      $ref: '#/components/schemas/hivemind_endpoints.hbd_asset'
      x-sql-datatype: JSON
      description: Estimated curation reward across the account''s pending votes
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.pending_curation_rewards CASCADE;
CREATE TYPE hivemind_endpoints.pending_curation_rewards AS (
    "account" TEXT,
    "pending_vote_count" INT,
    "estimated_curation_payout" JSON
);
-- openapi-generated-code-end
