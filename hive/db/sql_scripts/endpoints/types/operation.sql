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
hivemind_endpoints.asset:
  type: object
  x-sql-datatype: JSON
  properties:
    amount:
      type: string
      description: Asset amount in raw integer units (multiply by 10^-precision to get the decimal amount)
    precision:
      type: integer
      description: Decimal precision for the NAI asset
    nai:
      type: string
      description: Numeric Asset Identifier
 */

/** openapi:components:schemas
hivemind_endpoints.pending_reward_basis:
  type: object
  x-sql-datatype: JSON
  properties:
    liquid:
      $ref: '#/components/schemas/hivemind_endpoints.asset'
      description: HBD-denominated reward basis routed to liquid payout; final HBD/HIVE split requires exact hbd_print_rate outside Hivemind
    vesting:
      $ref: '#/components/schemas/hivemind_endpoints.asset'
      description: HBD-denominated reward basis routed to HP/VESTS; final VESTS amount requires exact reward vesting state outside Hivemind
    direct:
      $ref: '#/components/schemas/hivemind_endpoints.asset'
      description: HBD-denominated reward basis for direct-HBD paths such as treasury beneficiaries
    total:
      $ref: '#/components/schemas/hivemind_endpoints.asset'
      description: Sum of the visible liquid, vesting, and direct HBD-denominated reward-basis buckets
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
    gross_reward_basis:
      $ref: '#/components/schemas/hivemind_endpoints.asset'
      x-sql-datatype: JSON
      description: Sum of pending reward basis across all unpaid posts, capped by max_accepted_payout
    author_reward_basis:
      $ref: '#/components/schemas/hivemind_endpoints.pending_reward_basis'
      x-sql-datatype: JSON
      description: Author reward basis after beneficiary split; not final HBD/HIVE/VESTS payout
    beneficiaries_reward_basis:
      $ref: '#/components/schemas/hivemind_endpoints.pending_reward_basis'
      x-sql-datatype: JSON
      description: Beneficiary reward basis, including direct-HBD treasury beneficiary basis when present; not final HBD/HIVE/VESTS payout
    curators_reward_basis:
      $ref: '#/components/schemas/hivemind_endpoints.pending_reward_basis'
      x-sql-datatype: JSON
      description: Curator reward basis for the account''s posts; curation resolves to HP/VESTS outside Hivemind
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.pending_author_rewards CASCADE;
CREATE TYPE hivemind_endpoints.pending_author_rewards AS (
    "account" TEXT,
    "pending_post_count" INT,
    "gross_reward_basis" JSON,
    "author_reward_basis" JSON,
    "beneficiaries_reward_basis" JSON,
    "curators_reward_basis" JSON
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
    curation_reward_basis:
      $ref: '#/components/schemas/hivemind_endpoints.pending_reward_basis'
      x-sql-datatype: JSON
      description: Curation reward basis across the account''s pending votes; resolves to HP/VESTS outside Hivemind
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.pending_curation_rewards CASCADE;
CREATE TYPE hivemind_endpoints.pending_curation_rewards AS (
    "account" TEXT,
    "pending_vote_count" INT,
    "curation_reward_basis" JSON
);
-- openapi-generated-code-end
