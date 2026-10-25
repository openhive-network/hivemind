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
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.reblog_status CASCADE;
CREATE TYPE hivemind_endpoints.reblog_status AS (
    "author" TEXT,
    "permlink" TEXT,
    "reblogged" BOOLEAN
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.array_of_reblog_status:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.reblog_status'
 */

/** openapi:components:schemas
hivemind_endpoints.vote_status:
  type: object
  properties:
    author:
      type: string
      description: Post author account name
    permlink:
      type: string
      description: Post permlink
    voted:
      type: boolean
      description: True if the observer has voted on this post
    vote_percent:
      type: integer
      description: Percent of the observer''s vote in basis points (10000 is a full upvote, negative for a downvote), 0 when the observer has not voted
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.vote_status CASCADE;
CREATE TYPE hivemind_endpoints.vote_status AS (
    "author" TEXT,
    "permlink" TEXT,
    "voted" BOOLEAN,
    "vote_percent" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.array_of_vote_status:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.vote_status'
 */

/** openapi:components:schemas
hivemind_endpoints.account_relationship:
  type: object
  properties:
    account:
      type: string
      description: Listed account name
    follows:
      type: boolean
      description: True if the account follows the listed account
    ignores:
      type: boolean
      description: True if the account ignores (mutes) the listed account
    blacklists:
      type: boolean
      description: True if the account blacklists the listed account
    follows_blacklists:
      type: boolean
      description: True if the account follows the listed account''s blacklist
    follows_muted:
      type: boolean
      description: True if the account follows the listed account''s mute list
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.account_relationship CASCADE;
CREATE TYPE hivemind_endpoints.account_relationship AS (
    "account" TEXT,
    "follows" BOOLEAN,
    "ignores" BOOLEAN,
    "blacklists" BOOLEAN,
    "follows_blacklists" BOOLEAN,
    "follows_muted" BOOLEAN
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.array_of_account_relationship:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.account_relationship'
 */

/** openapi:components:schemas
hivemind_endpoints.account_vote:
  type: object
  properties:
    author:
      type: string
      description: Author of the voted post
    permlink:
      type: string
      description: Permlink of the voted post
    weight:
      type: string
      description: Vote weight used for curation rewards, as a decimal integer string (can exceed 2^53)
    rshares:
      type: string
      description: Reward shares of the vote, as a decimal integer string (can exceed 2^53)
    vote_percent:
      type: integer
      description: Vote percent in basis points (10000 is a full upvote, negative for a downvote, 0 for a removed vote)
    last_update:
      type: string
      format: date-time
      description: Time the vote was cast or last changed
    num_changes:
      type: integer
      description: Number of times the vote was changed
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.account_vote CASCADE;
CREATE TYPE hivemind_endpoints.account_vote AS (
    "author" TEXT,
    "permlink" TEXT,
    "weight" TEXT,
    "rshares" TEXT,
    "vote_percent" INT,
    "last_update" TIMESTAMP,
    "num_changes" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.array_of_account_vote:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.account_vote'
 */

/** openapi:components:schemas
hivemind_endpoints.post_vote:
  type: object
  properties:
    voter:
      type: string
      description: Voter account name
    author:
      type: string
      description: Author of the voted post
    permlink:
      type: string
      description: Permlink of the voted post
    weight:
      type: string
      description: Vote weight used for curation rewards, as a decimal integer string (can exceed 2^53)
    rshares:
      type: string
      description: Reward shares of the vote, as a decimal integer string (can exceed 2^53)
    vote_percent:
      type: integer
      description: Vote percent in basis points (10000 is a full upvote, negative for a downvote, 0 for a removed vote)
    last_update:
      type: string
      format: date-time
      description: Time the vote was cast or last changed
    num_changes:
      type: integer
      description: Number of times the vote was changed
 */
-- openapi-generated-code-begin
DROP TYPE IF EXISTS hivemind_endpoints.post_vote CASCADE;
CREATE TYPE hivemind_endpoints.post_vote AS (
    "voter" TEXT,
    "author" TEXT,
    "permlink" TEXT,
    "weight" TEXT,
    "rshares" TEXT,
    "vote_percent" INT,
    "last_update" TIMESTAMP,
    "num_changes" INT
);
-- openapi-generated-code-end

/** openapi:components:schemas
hivemind_endpoints.array_of_post_vote:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.post_vote'
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

/** openapi:components:schemas
hivemind_endpoints.bridge_post:
  type: object
  x-sql-datatype: JSONB
  description: A post or comment as returned by `bridge.get_post`
  properties:
    author:
      type: string
    permlink:
      type: string
    category:
      type: string
    title:
      type: string
    body:
      type: string
    json_metadata:
      type: object
    created:
      type: string
      format: date-time
    updated:
      type: string
      format: date-time
    depth:
      type: integer
    children:
      type: integer
    net_rshares:
      type: integer
    is_paidout:
      type: boolean
    payout_at:
      type: string
      format: date-time
    payout:
      type: number
    pending_payout_value:
      type: string
    author_payout_value:
      type: string
    curator_payout_value:
      type: string
    promoted:
      type: string
    replies:
      type: array
      items:
        type: string
    active_votes:
      type: array
      items:
        type: object
    author_reputation:
      type: number
    stats:
      type: object
    url:
      type: string
    beneficiaries:
      type: array
      items:
        type: object
    max_accepted_payout:
      type: string
    percent_hbd:
      type: integer
    parent_author:
      type: string
    parent_permlink:
      type: string
    blacklists:
      type: array
      items:
        type: string
    community:
      type: string
    community_title:
      type: string
    author_role:
      type: string
    author_title:
      type: string
    reblogs:
      type: integer
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_bridge_post:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.bridge_post'
 */

/** openapi:components:schemas
hivemind_endpoints.bridge_profile:
  type: object
  x-sql-datatype: JSONB
  description: An account profile as returned by `bridge.get_profile`
  properties:
    id:
      type: integer
    name:
      type: string
    created:
      type: string
      format: date-time
    active:
      type: string
      format: date-time
    post_count:
      type: integer
    reputation:
      type: number
    blacklists:
      type: array
      items:
        type: string
    stats:
      type: object
    metadata:
      type: object
    context:
      type: object
 */

/** openapi:components:schemas
hivemind_endpoints.follow:
  type: object
  x-sql-datatype: JSONB
  description: A follow relation as returned by `condenser_api.get_followers` and `get_following`
  properties:
    follower:
      type: string
    following:
      type: string
    what:
      type: array
      items:
        type: string
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_follow:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.follow'
 */

/** openapi:components:schemas
hivemind_endpoints.notification:
  type: object
  x-sql-datatype: JSONB
  description: A notification as returned by `bridge.account_notifications`
  properties:
    id:
      type: string
    type:
      type: string
    score:
      type: integer
    date:
      type: string
      format: date-time
    msg:
      type: string
    url:
      type: string
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_notification:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.notification'
 */

/** openapi:components:schemas
hivemind_endpoints.bridge_community:
  type: object
  x-sql-datatype: JSONB
  description: A community as returned by `bridge.get_community` and `bridge.list_communities`
  properties:
    id:
      type: integer
    name:
      type: string
    title:
      type: string
    about:
      type: string
    description:
      type: string
    flag_text:
      type: string
    lang:
      type: string
    is_nsfw:
      type: boolean
    type_id:
      type: integer
    created_at:
      type: string
    subscribers:
      type: integer
    sum_pending:
      type: number
    num_pending:
      type: integer
    num_authors:
      type: integer
    admins:
      type: array
      items:
        type: string
    team:
      type: array
      items:
        type: array
        items:
          type: string
    settings:
      type: object
    context:
      type: object
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_bridge_community:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.bridge_community'
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_string_tuple:
  type: array
  description: Rows given as arrays of strings, as several bridge methods return them
  items:
    type: array
    items:
      type: ["string", "null"]
 */

/** openapi:components:schemas
hivemind_endpoints.discussion:
  type: object
  x-sql-datatype: JSONB
  description: |
    A thread as returned by `bridge.get_discussion`: each of its posts keyed by `author/permlink`,
    the post itself included; each post''s `replies` names its direct replies in the thread
  additionalProperties:
    $ref: '#/components/schemas/hivemind_endpoints.bridge_post'
 */

/** openapi:components:schemas
hivemind_endpoints.follow_list_entry:
  type: object
  x-sql-datatype: JSONB
  description: An account of a list as returned by `bridge.get_follow_list`
  properties:
    name:
      type: string
    blacklist_description:
      type: ["string", "null"]
    muted_list_description:
      type: ["string", "null"]
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_follow_list_entry:
  type: array
  items:
    $ref: '#/components/schemas/hivemind_endpoints.follow_list_entry'
 */

/** openapi:components:schemas
hivemind_endpoints.post_header:
  type: object
  x-sql-datatype: JSONB
  description: A post''s header as returned by `bridge.get_post_header`
  properties:
    author:
      type: string
    permlink:
      type: string
    category:
      type: string
    depth:
      type: integer
 */

/** openapi:components:schemas
hivemind_endpoints.unread_notifications:
  type: object
  x-sql-datatype: JSONB
  description: An account''s unread notification count as returned by `bridge.unread_notifications`
  properties:
    lastread:
      type: string
      description: When the account last marked its notifications read, `YYYY-MM-DD HH24:MI:SS`
    unread:
      type: integer
      description: Number of notifications of the last 90 days after `lastread`
 */

/** openapi:components:schemas
hivemind_endpoints.array_of_string:
  type: array
  items:
    type: string
 */
