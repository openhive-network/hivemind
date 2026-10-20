/** openapi
openapi: 3.1.0
info:
  title: Hivemind
  description: >-
    Hivemind is a microservice that simplifies data access and enables the development of rich social media applications on top of the Hive blockchain. 
    It maintains the state of social features such as post feeds, follows, and communities, providing a consensus interpretation layer for Hive applications.
  license:
    name: MIT License
    url: https://opensource.org/license/mit
  version: 0.0.0-dev
externalDocs:
  description: Hivemind gitlab repository
  url: https://gitlab.syncad.com/hive/hivemind
tags:
  - name: blog_api
    description: 
  - name: Other
    description: General API information
servers:
  - url: /hivemind-api
 */

DO $__$
DECLARE 
  __schema_name VARCHAR;
  __swagger_url TEXT;
BEGIN
  SHOW SEARCH_PATH INTO __schema_name;
  __swagger_url := current_setting('custom.swagger_url')::TEXT;

EXECUTE FORMAT(
'create or replace function hivemind_endpoints.home() returns json as $_$
declare
-- openapi-spec
-- openapi-generated-code-begin
  openapi json = $$
{
  "openapi": "3.1.0",
  "info": {
    "title": "Hivemind",
    "description": "Hivemind is a microservice that simplifies data access and enables the development of rich social media applications on top of the Hive blockchain.  It maintains the state of social features such as post feeds, follows, and communities, providing a consensus interpretation layer for Hive applications.",
    "license": {
      "name": "MIT License",
      "url": "https://opensource.org/license/mit"
    },
    "version": "0.0.0-dev"
  },
  "externalDocs": {
    "description": "Hivemind gitlab repository",
    "url": "https://gitlab.syncad.com/hive/hivemind"
  },
  "tags": [
    {
      "name": "blog_api",
      "description": null
    },
    {
      "name": "Other",
      "description": "General API information"
    }
  ],
  "servers": [
    {
      "url": "/hivemind-api"
    }
  ],
  "components": {
    "schemas": {
      "hivemind_endpoints.block_range_type": {
        "type": "object",
        "properties": {
          "from": {
            "type": "integer"
          },
          "to": {
            "type": "integer"
          }
        }
      },
      "hivemind_endpoints.operation_body": {
        "type": "object",
        "x-sql-datatype": "JSON",
        "properties": {
          "type": {
            "type": "string"
          },
          "value": {
            "type": "object"
          }
        }
      },
      "hivemind_endpoints.array_of_operations": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.operation_body"
        }
      },
      "hivemind_endpoints.operation": {
        "type": "object",
        "properties": {
          "op": {
            "$ref": "#/components/schemas/hivemind_endpoints.operation_body",
            "x-sql-datatype": "JSONB",
            "description": "operation body"
          },
          "block": {
            "type": "integer",
            "description": "block containing the operation"
          },
          "trx_id": {
            "type": [
              "string",
              "null"
            ],
            "description": "hash of the transaction"
          },
          "op_pos": {
            "type": "integer",
            "description": "operation identifier that indicates its sequence number in transaction"
          },
          "op_type_id": {
            "type": "integer",
            "description": "operation type identifier"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "creation date"
          },
          "virtual_op": {
            "type": "boolean",
            "description": "true if is a virtual operation"
          },
          "operation_id": {
            "type": "string",
            "description": "unique operation identifier with an encoded block number and operation type id"
          },
          "trx_in_block": {
            "type": "integer",
            "x-sql-datatype": "SMALLINT",
            "description": "transaction identifier that indicates its sequence number in block"
          }
        }
      },
      "hivemind_endpoints.operation_history": {
        "type": "object",
        "properties": {
          "total_operations": {
            "type": "integer",
            "description": "Total number of operations"
          },
          "total_pages": {
            "type": "integer",
            "description": "Total number of pages"
          },
          "block_range": {
            "$ref": "#/components/schemas/hivemind_endpoints.block_range_type",
            "description": "Range of blocks that contains the returned pages"
          },
          "operations_result": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hivemind_endpoints.operation"
            },
            "description": "List of operation results"
          }
        }
      },
      "hivemind_endpoints.reblog_status": {
        "type": "object",
        "properties": {
          "author": {
            "type": "string",
            "description": "Post author account name"
          },
          "permlink": {
            "type": "string",
            "description": "Post permlink"
          },
          "reblogged": {
            "type": "boolean",
            "description": "True if the observer has reblogged this post"
          }
        }
      },
      "hivemind_endpoints.array_of_reblog_status": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.reblog_status"
        }
      },
      "hivemind_endpoints.vote_status": {
        "type": "object",
        "properties": {
          "author": {
            "type": "string",
            "description": "Post author account name"
          },
          "permlink": {
            "type": "string",
            "description": "Post permlink"
          },
          "voted": {
            "type": "boolean",
            "description": "True if the observer has voted on this post"
          },
          "vote_percent": {
            "type": "integer",
            "description": "Percent of the observer''s vote in basis points (10000 is a full upvote, negative for a downvote), 0 when the observer has not voted"
          }
        }
      },
      "hivemind_endpoints.array_of_vote_status": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.vote_status"
        }
      },
      "hivemind_endpoints.account_relationship": {
        "type": "object",
        "properties": {
          "account": {
            "type": "string",
            "description": "Listed account name"
          },
          "follows": {
            "type": "boolean",
            "description": "True if the account follows the listed account"
          },
          "ignores": {
            "type": "boolean",
            "description": "True if the account ignores (mutes) the listed account"
          },
          "blacklists": {
            "type": "boolean",
            "description": "True if the account blacklists the listed account"
          },
          "follows_blacklists": {
            "type": "boolean",
            "description": "True if the account follows the listed account''s blacklist"
          },
          "follows_muted": {
            "type": "boolean",
            "description": "True if the account follows the listed account''s mute list"
          }
        }
      },
      "hivemind_endpoints.array_of_account_relationship": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.account_relationship"
        }
      },
      "hivemind_endpoints.account_vote": {
        "type": "object",
        "properties": {
          "author": {
            "type": "string",
            "description": "Author of the voted post"
          },
          "permlink": {
            "type": "string",
            "description": "Permlink of the voted post"
          },
          "weight": {
            "type": "string",
            "description": "Vote weight used for curation rewards, as a decimal integer string (can exceed 2^53)"
          },
          "rshares": {
            "type": "string",
            "description": "Reward shares of the vote, as a decimal integer string (can exceed 2^53)"
          },
          "vote_percent": {
            "type": "integer",
            "description": "Vote percent in basis points (10000 is a full upvote, negative for a downvote, 0 for a removed vote)"
          },
          "last_update": {
            "type": "string",
            "format": "date-time",
            "description": "Time the vote was cast or last changed"
          },
          "num_changes": {
            "type": "integer",
            "description": "Number of times the vote was changed"
          }
        }
      },
      "hivemind_endpoints.array_of_account_vote": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.account_vote"
        }
      },
      "hivemind_endpoints.post_vote": {
        "type": "object",
        "properties": {
          "voter": {
            "type": "string",
            "description": "Voter account name"
          },
          "author": {
            "type": "string",
            "description": "Author of the voted post"
          },
          "permlink": {
            "type": "string",
            "description": "Permlink of the voted post"
          },
          "weight": {
            "type": "string",
            "description": "Vote weight used for curation rewards, as a decimal integer string (can exceed 2^53)"
          },
          "rshares": {
            "type": "string",
            "description": "Reward shares of the vote, as a decimal integer string (can exceed 2^53)"
          },
          "vote_percent": {
            "type": "integer",
            "description": "Vote percent in basis points (10000 is a full upvote, negative for a downvote, 0 for a removed vote)"
          },
          "last_update": {
            "type": "string",
            "format": "date-time",
            "description": "Time the vote was cast or last changed"
          },
          "num_changes": {
            "type": "integer",
            "description": "Number of times the vote was changed"
          }
        }
      },
      "hivemind_endpoints.array_of_post_vote": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.post_vote"
        }
      },
      "hivemind_endpoints.asset": {
        "type": "object",
        "x-sql-datatype": "JSON",
        "properties": {
          "amount": {
            "type": "string",
            "description": "Asset amount in raw integer units (multiply by 10^-precision to get the decimal amount)"
          },
          "precision": {
            "type": "integer",
            "description": "Decimal precision for the NAI asset"
          },
          "nai": {
            "type": "string",
            "description": "Numeric Asset Identifier"
          }
        }
      },
      "hivemind_endpoints.pending_reward_basis": {
        "type": "object",
        "x-sql-datatype": "JSON",
        "properties": {
          "liquid": {
            "$ref": "#/components/schemas/hivemind_endpoints.asset",
            "description": "HBD-denominated reward basis routed to liquid payout; final HBD/HIVE split requires exact hbd_print_rate outside Hivemind"
          },
          "vesting": {
            "$ref": "#/components/schemas/hivemind_endpoints.asset",
            "description": "HBD-denominated reward basis routed to HP/VESTS; final VESTS amount requires exact reward vesting state outside Hivemind"
          },
          "direct": {
            "$ref": "#/components/schemas/hivemind_endpoints.asset",
            "description": "HBD-denominated reward basis for direct-HBD paths such as treasury beneficiaries"
          },
          "total": {
            "$ref": "#/components/schemas/hivemind_endpoints.asset",
            "description": "Sum of the visible liquid, vesting, and direct HBD-denominated reward-basis buckets"
          }
        }
      },
      "hivemind_endpoints.pending_author_rewards": {
        "type": "object",
        "properties": {
          "account": {
            "type": "string",
            "description": "Account name"
          },
          "pending_post_count": {
            "type": "integer",
            "description": "Number of posts awaiting payout"
          },
          "gross_reward_basis": {
            "$ref": "#/components/schemas/hivemind_endpoints.asset",
            "x-sql-datatype": "JSON",
            "description": "Sum of pending reward basis across all unpaid posts, capped by max_accepted_payout"
          },
          "author_reward_basis": {
            "$ref": "#/components/schemas/hivemind_endpoints.pending_reward_basis",
            "x-sql-datatype": "JSON",
            "description": "Author reward basis after beneficiary split; not final HBD/HIVE/VESTS payout"
          },
          "beneficiaries_reward_basis": {
            "$ref": "#/components/schemas/hivemind_endpoints.pending_reward_basis",
            "x-sql-datatype": "JSON",
            "description": "Beneficiary reward basis, including direct-HBD treasury beneficiary basis when present; not final HBD/HIVE/VESTS payout"
          },
          "curators_reward_basis": {
            "$ref": "#/components/schemas/hivemind_endpoints.pending_reward_basis",
            "x-sql-datatype": "JSON",
            "description": "Curator reward basis for the account''s posts; curation resolves to HP/VESTS outside Hivemind"
          }
        }
      },
      "hivemind_endpoints.pending_curation_rewards": {
        "type": "object",
        "properties": {
          "account": {
            "type": "string",
            "description": "Account name"
          },
          "pending_vote_count": {
            "type": "integer",
            "description": "Number of recent votes awaiting payout (within the last 8 chain-days)"
          },
          "curation_reward_basis": {
            "$ref": "#/components/schemas/hivemind_endpoints.pending_reward_basis",
            "x-sql-datatype": "JSON",
            "description": "Curation reward basis across the account''s pending votes; resolves to HP/VESTS outside Hivemind"
          }
        }
      },
      "hivemind_endpoints.bridge_post": {
        "type": "object",
        "x-sql-datatype": "JSONB",
        "description": "A post or comment as returned by `bridge.get_post`",
        "properties": {
          "author": {
            "type": "string"
          },
          "permlink": {
            "type": "string"
          },
          "category": {
            "type": "string"
          },
          "title": {
            "type": "string"
          },
          "body": {
            "type": "string"
          },
          "json_metadata": {
            "type": "object"
          },
          "created": {
            "type": "string",
            "format": "date-time"
          },
          "updated": {
            "type": "string",
            "format": "date-time"
          },
          "depth": {
            "type": "integer"
          },
          "children": {
            "type": "integer"
          },
          "net_rshares": {
            "type": "integer"
          },
          "is_paidout": {
            "type": "boolean"
          },
          "payout_at": {
            "type": "string",
            "format": "date-time"
          },
          "payout": {
            "type": "number"
          },
          "pending_payout_value": {
            "type": "string"
          },
          "author_payout_value": {
            "type": "string"
          },
          "curator_payout_value": {
            "type": "string"
          },
          "promoted": {
            "type": "string"
          },
          "replies": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "active_votes": {
            "type": "array",
            "items": {
              "type": "object"
            }
          },
          "author_reputation": {
            "type": "number"
          },
          "stats": {
            "type": "object"
          },
          "url": {
            "type": "string"
          },
          "beneficiaries": {
            "type": "array",
            "items": {
              "type": "object"
            }
          },
          "max_accepted_payout": {
            "type": "string"
          },
          "percent_hbd": {
            "type": "integer"
          },
          "parent_author": {
            "type": "string"
          },
          "parent_permlink": {
            "type": "string"
          },
          "blacklists": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "community": {
            "type": "string"
          },
          "community_title": {
            "type": "string"
          },
          "author_role": {
            "type": "string"
          },
          "author_title": {
            "type": "string"
          },
          "reblogs": {
            "type": "integer"
          }
        }
      },
      "hivemind_endpoints.array_of_bridge_post": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.bridge_post"
        }
      },
      "hivemind_endpoints.bridge_profile": {
        "type": "object",
        "x-sql-datatype": "JSONB",
        "description": "An account profile as returned by `bridge.get_profile`",
        "properties": {
          "id": {
            "type": "integer"
          },
          "name": {
            "type": "string"
          },
          "created": {
            "type": "string",
            "format": "date-time"
          },
          "active": {
            "type": "string",
            "format": "date-time"
          },
          "post_count": {
            "type": "integer"
          },
          "reputation": {
            "type": "number"
          },
          "blacklists": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "stats": {
            "type": "object"
          },
          "metadata": {
            "type": "object"
          },
          "context": {
            "type": "object"
          }
        }
      },
      "hivemind_endpoints.follow": {
        "type": "object",
        "x-sql-datatype": "JSONB",
        "description": "A follow relation as returned by `condenser_api.get_followers` and `get_following`",
        "properties": {
          "follower": {
            "type": "string"
          },
          "following": {
            "type": "string"
          },
          "what": {
            "type": "array",
            "items": {
              "type": "string"
            }
          }
        }
      },
      "hivemind_endpoints.array_of_follow": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.follow"
        }
      },
      "hivemind_endpoints.notification": {
        "type": "object",
        "x-sql-datatype": "JSONB",
        "description": "A notification as returned by `bridge.account_notifications`",
        "properties": {
          "id": {
            "type": "string"
          },
          "type": {
            "type": "string"
          },
          "score": {
            "type": "integer"
          },
          "date": {
            "type": "string",
            "format": "date-time"
          },
          "msg": {
            "type": "string"
          },
          "url": {
            "type": "string"
          }
        }
      },
      "hivemind_endpoints.array_of_notification": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.notification"
        }
      },
      "hivemind_endpoints.bridge_community": {
        "type": "object",
        "x-sql-datatype": "JSONB",
        "description": "A community as returned by `bridge.get_community` and `bridge.list_communities`",
        "properties": {
          "id": {
            "type": "integer"
          },
          "name": {
            "type": "string"
          },
          "title": {
            "type": "string"
          },
          "about": {
            "type": "string"
          },
          "description": {
            "type": "string"
          },
          "flag_text": {
            "type": "string"
          },
          "lang": {
            "type": "string"
          },
          "is_nsfw": {
            "type": "boolean"
          },
          "type_id": {
            "type": "integer"
          },
          "created_at": {
            "type": "string"
          },
          "subscribers": {
            "type": "integer"
          },
          "sum_pending": {
            "type": "number"
          },
          "num_pending": {
            "type": "integer"
          },
          "num_authors": {
            "type": "integer"
          },
          "admins": {
            "type": "array",
            "items": {
              "type": "string"
            }
          },
          "team": {
            "type": "array",
            "items": {
              "type": "array",
              "items": {
                "type": "string"
              }
            }
          },
          "settings": {
            "type": "object"
          },
          "context": {
            "type": "object"
          }
        }
      },
      "hivemind_endpoints.array_of_bridge_community": {
        "type": "array",
        "items": {
          "$ref": "#/components/schemas/hivemind_endpoints.bridge_community"
        }
      },
      "hivemind_endpoints.array_of_string_tuple": {
        "type": "array",
        "description": "Rows given as arrays of strings, as several bridge methods return them",
        "items": {
          "type": "array",
          "items": {
            "type": [
              "string",
              "null"
            ]
          }
        }
      }
    }
  },
  "paths": {
    "/accounts/{account-name}/operations": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get operations for an account by recency.",
        "description": "List the non-virtual operations in reversed order (first page is the oldest) for given account. \nThe page size determines the number of operations per page.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_ops_by_account(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/blocktrades/operations?page-size=3''`\n",
        "operationId": "hivemind_endpoints.get_ops_by_account",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account to get operations for."
          },
          {
            "in": "query",
            "name": "observer-name",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account name of the observer"
          },
          {
            "in": "query",
            "name": "operation-types",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "List of operation types to get. If NULL, gets all non-virtual operation types.\nexample: `18,12`\n"
          },
          {
            "in": "query",
            "name": "page",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Return page on `page` number, default null due to reversed order of pages,\nthe first page is the oldest,\nexample: first call returns the newest page and total_pages is 100 - the newest page is number 100, next 99 etc.\n"
          },
          {
            "in": "query",
            "name": "page-size",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 100
            },
            "description": "Return max `page-size` operations per page, defaults to `100`."
          },
          {
            "in": "query",
            "name": "data-size-limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 200000
            },
            "description": "If the operation length exceeds the data size limit,\nthe operation body is replaced with a placeholder (defaults to `200000`).\n"
          },
          {
            "in": "query",
            "name": "from-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Lower limit of the block range, can be represented either by a block-number (integer) or a timestamp (in the format YYYY-MM-DD HH:MI:SS).\n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is more than or equal to the given `timestamp` (i.e. `block''s created_at >= timestamp`).\n\nThe function will interpret and convert the input based on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          },
          {
            "in": "query",
            "name": "to-block",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Similar to the from-block parameter, can either be a block-number (integer) or a timestamp (formatted as YYYY-MM-DD HH:MI:SS). \n\nThe provided `timestamp` will be converted to a `block-num` by finding the first block \nwhere the block''s `created_at` is less than or equal to the given `timestamp` (i.e. `block''s created_at <= timestamp`).\n\nThe function will convert the value depending on its format, example input:\n\n* `2016-09-15 19:47:21`\n\n* `5000000`\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Result contains total number of operations,\ntotal pages, and the list of operations.\n\n* Returns `hivemind_endpoints.operation_history`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.operation_history"
                },
                "example": {
                  "total_operations": 219867,
                  "total_pages": 73289,
                  "block_range": {
                    "from": 1,
                    "to": 5000000
                  },
                  "operations_result": [
                    {
                      "op": {
                        "type": "transfer_operation",
                        "value": {
                          "to": "blocktrades",
                          "from": "mrwang",
                          "memo": "a79c09cd-0084-4cd4-ae63-bf6d2514fef9",
                          "amount": {
                            "nai": "@@000000013",
                            "amount": "1633",
                            "precision": 3
                          }
                        }
                      },
                      "block": 4999997,
                      "trx_id": "e75f833ceb62570c25504b55d0f23d86d9d76423",
                      "op_pos": 0,
                      "op_type_id": 2,
                      "timestamp": "2016-09-15T19:47:12",
                      "virtual_op": false,
                      "operation_id": "21474823595099394",
                      "trx_in_block": 3
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/accounts/{account-name}/pending-author-rewards": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get pending (pre-payout) author rewards for an account.",
        "description": "Returns the aggregated pending author and beneficiary rewards across all\nof the account''s posts that have not yet reached payout (i.e. `is_paidout = false`\nand not deleted). For each unpaid post the gross pending payout is capped by\n`max_accepted_payout` and is split between the author and the beneficiaries.\nPosts that declined payout (`is_declined = true`) contribute zero.\nThe response intentionally does not expose final HBD/HIVE/VESTS payout\nassets. Hivemind does not have exact HBD print-rate and reward-vesting\nstate, so the endpoint returns only HBD-denominated reward basis values\nsplit into liquid, vesting, and direct buckets.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_account_pending_author_rewards(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/blocktrades/pending-author-rewards''`\n",
        "operationId": "hivemind_endpoints.get_account_pending_author_rewards",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account to get pending author rewards for."
          }
        ],
        "responses": {
          "200": {
            "description": "Aggregated pending author rewards.\n\n* Returns `hivemind_endpoints.pending_author_rewards`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.pending_author_rewards"
                },
                "example": {
                  "account": "blocktrades",
                  "pending_post_count": 1,
                  "gross_reward_basis": {
                    "amount": "2000",
                    "precision": 3,
                    "nai": "@@000000013"
                  },
                  "author_reward_basis": {
                    "liquid": {
                      "amount": "500",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "vesting": {
                      "amount": "500",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "direct": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "total": {
                      "amount": "1000",
                      "precision": 3,
                      "nai": "@@000000013"
                    }
                  },
                  "beneficiaries_reward_basis": {
                    "liquid": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "vesting": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "direct": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "total": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    }
                  },
                  "curators_reward_basis": {
                    "liquid": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "vesting": {
                      "amount": "1000",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "direct": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "total": {
                      "amount": "1000",
                      "precision": 3,
                      "nai": "@@000000013"
                    }
                  }
                }
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/accounts/{account-name}/pending-curation-rewards": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get pending (pre-payout) curation rewards for an account.",
        "description": "Returns the aggregated curation reward basis for the account, summed\nacross all of the account''s votes on posts that have not yet reached payout.\nOnly votes cast within the last eight chain-days (relative to the head block)\nare considered, matching the chain''s curation reward window. Posts that\ndeclined payout or disabled curation rewards contribute zero.\nCuration rewards resolve to HP/VESTS outside Hivemind. This endpoint returns\nonly the HBD-denominated reward basis, not final VESTS/HBD/HIVE payout assets.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_account_pending_curation_rewards(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/blocktrades/pending-curation-rewards''`\n",
        "operationId": "hivemind_endpoints.get_account_pending_curation_rewards",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account to get pending curation rewards for."
          }
        ],
        "responses": {
          "200": {
            "description": "Aggregated pending curation rewards.\n\n* Returns `hivemind_endpoints.pending_curation_rewards`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.pending_curation_rewards"
                },
                "example": {
                  "account": "blocktrades",
                  "pending_vote_count": 1,
                  "curation_reward_basis": {
                    "liquid": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "vesting": {
                      "amount": "1000",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "direct": {
                      "amount": "0",
                      "precision": 3,
                      "nai": "@@000000013"
                    },
                    "total": {
                      "amount": "1000",
                      "precision": 3,
                      "nai": "@@000000013"
                    }
                  }
                }
              }
            }
          },
          "404": {
            "description": "No such account in the database"
          }
        }
      }
    },
    "/accounts/{account-name}/relationships": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get the relationship of an account to each of a list of accounts",
        "description": "Returns, for each listed account, whether the account follows, ignores (mutes) or blacklists it,\nand whether the account follows its blacklist or its mute list, the same fields as\n`bridge.get_relationship_between_accounts`. One row is returned per distinct listed account,\nin the order they are listed.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_account_relationships(''alice'', ''bob,carol'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/alice/relationships?accounts=bob,carol''`\n",
        "operationId": "hivemind_endpoints.get_account_relationships",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account whose relationships are returned"
          },
          {
            "in": "query",
            "name": "accounts",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Comma-separated list of at most 100 account names"
          }
        ],
        "responses": {
          "200": {
            "description": "Relationship of the account to each listed account\n\n* Returns `SETOF hivemind_endpoints.account_relationship`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_account_relationship"
                },
                "example": [
                  {
                    "account": "bob",
                    "follows": true,
                    "ignores": false,
                    "blacklists": false,
                    "follows_blacklists": false,
                    "follows_muted": false
                  }
                ]
              }
            }
          },
          "400": {
            "description": "Unknown account, missing or invalid account list, or more than 100 listed accounts"
          }
        }
      }
    },
    "/accounts/{account-name}/votes": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get votes cast by an account, newest first",
        "description": "Returns the votes cast by the account ordered by the time each vote was last updated, newest first\n(ties are broken by the vote''s internal id, newest first).\n\nTo fetch the next page pass the `last_update`, `author` and `permlink` of the last vote of the\nprevious page as `before`, `start-author` and `start-permlink`; consecutive pages then neither\nrepeat nor skip a vote. `before` alone returns the votes last updated strictly before that time.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_account_votes(''blocktrades'', 20);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/blocktrades/votes?limit=20''`\n* `GET ''https://%1$s/hivemind-api/accounts/blocktrades/votes?limit=20&before=2016-09-15T19:47:21&start-author=alice&start-permlink=my-awesome-post''`\n",
        "operationId": "hivemind_endpoints.get_account_votes",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account whose votes are listed"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 20,
              "minimum": 1
            },
            "description": "Maximum number of votes to return"
          },
          {
            "in": "query",
            "name": "before",
            "required": false,
            "schema": {
              "type": "string",
              "format": "date-time",
              "default": null
            },
            "description": "Return votes last updated before this time (`last_update` of the last vote of the previous page)"
          },
          {
            "in": "query",
            "name": "start-author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Author of the post of the last vote of the previous page"
          },
          {
            "in": "query",
            "name": "start-permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Permlink of the post of the last vote of the previous page"
          }
        ],
        "responses": {
          "200": {
            "description": "Votes cast by the account, newest first\n\n* Returns `SETOF hivemind_endpoints.account_vote`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_account_vote"
                },
                "example": [
                  {
                    "author": "alice",
                    "permlink": "my-awesome-post",
                    "weight": "1146353766",
                    "rshares": "1879215360",
                    "vote_percent": 10000,
                    "last_update": "2016-09-15T19:47:21",
                    "num_changes": 0
                  }
                ]
              }
            }
          },
          "400": {
            "description": "Unknown account, unknown start post, or the account has not voted on the start post"
          }
        }
      }
    },
    "/accounts/{account-name}/posts": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get an account''s posts",
        "description": "Returns the account''s posts of the kind given by `sort`, the same list as `bridge.get_account_posts`.\n\nTo fetch the next page pass the `author` and `permlink` of the last post of the previous page\nas `start-author` and `start-permlink`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_account_posts(''alice'', ''blog'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/alice/posts?sort=blog&limit=20''`\n",
        "operationId": "hivemind_endpoints.get_account_posts",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account whose posts are listed"
          },
          {
            "in": "query",
            "name": "sort",
            "required": true,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Kind of posts: `blog`, `feed`, `posts`, `comments`, `replies` or `payout`\n"
          },
          {
            "in": "query",
            "name": "community",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Only posts in this community; allowed with `sort` `posts` and `comments`"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of posts to return, at most the posts-per-call limit (20 unless configured), which is also the default"
          },
          {
            "in": "query",
            "name": "start-author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Author of the last post of the previous page"
          },
          {
            "in": "query",
            "name": "start-permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Permlink of the last post of the previous page"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose mutes and blacklists are applied. The response without an observer\nis the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The account''s posts\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_bridge_post",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown account, community or start post, unsupported sort, or an invalid parameter"
          }
        }
      }
    },
    "/accounts/{account-name}/profile": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get an account''s profile",
        "description": "Returns the account''s profile, the same object as `bridge.get_profile`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_account_profile(''alice'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/alice/profile''`\n",
        "operationId": "hivemind_endpoints.get_account_profile",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account whose profile is returned"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose relationship to the profiled account is reported in `context`. The response\nwithout an observer is the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The account''s profile\n\n* Returns `JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.bridge_profile",
                  "x-sql-datatype": "JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown account or an invalid parameter"
          }
        }
      }
    },
    "/accounts/{account-name}/followers": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get an account''s followers",
        "description": "Returns the accounts that follow (or, with `type=ignore`, mute) the account, the same list as `condenser_api.get_followers`,\nin alphabetical order.\n\nTo fetch the next page pass the last account of the previous page as `start`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_account_followers(''alice'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/alice/followers?type=blog&limit=100''`\n",
        "operationId": "hivemind_endpoints.get_account_followers",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account whose followers are listed"
          },
          {
            "in": "query",
            "name": "type",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "`blog` (follows, the default) or `ignore` (mutes)"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of accounts to return, at most 1000 (the default)"
          },
          {
            "in": "query",
            "name": "start",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Last account of the previous page"
          }
        ],
        "responses": {
          "200": {
            "description": "Follow relations\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_follow",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown account or start account, unsupported type, or an invalid parameter"
          }
        }
      }
    },
    "/accounts/{account-name}/following": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get the accounts an account follows",
        "description": "Returns the accounts the account follows (or, with `type=ignore`, mutes), the same list as `condenser_api.get_following`,\nin alphabetical order.\n\nTo fetch the next page pass the last account of the previous page as `start`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_account_following(''alice'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/alice/following?type=blog&limit=100''`\n",
        "operationId": "hivemind_endpoints.get_account_following",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account whose following are listed"
          },
          {
            "in": "query",
            "name": "type",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "`blog` (follows, the default) or `ignore` (mutes)"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of accounts to return, at most 1000 (the default)"
          },
          {
            "in": "query",
            "name": "start",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Last account of the previous page"
          }
        ],
        "responses": {
          "200": {
            "description": "Follow relations\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_follow",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown account or start account, unsupported type, or an invalid parameter"
          }
        }
      }
    },
    "/accounts/{account-name}/notifications": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get an account''s notifications",
        "description": "Returns the account''s notifications of the last 90 days, newest first, the same list as\n`bridge.account_notifications`.\n\nTo fetch the next page pass the `id` of the last notification of the previous page as `last-id`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_account_notifications(''alice'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/alice/notifications?type=reply,mention&limit=50''`\n",
        "operationId": "hivemind_endpoints.get_account_notifications",
        "parameters": [
          {
            "in": "path",
            "name": "account-name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Account whose notifications are listed"
          },
          {
            "in": "query",
            "name": "type",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Comma-separated notification types to return, e.g. `reply,mention`; all types when absent\n"
          },
          {
            "in": "query",
            "name": "community",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Only notifications about this community"
          },
          {
            "in": "query",
            "name": "min-score",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Minimum notification score, 0 to 100, 25 by default"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of notifications to return, at most 100 (the default)"
          },
          {
            "in": "query",
            "name": "last-id",
            "required": false,
            "schema": {
              "type": "integer",
              "x-sql-datatype": "BIGINT",
              "default": null
            },
            "description": "Id of the last notification of the previous page"
          }
        ],
        "responses": {
          "200": {
            "description": "The account''s notifications\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_notification",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown account or community, unknown notification type, or an invalid parameter"
          }
        }
      }
    },
    "/blog/reblogs": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get reblog status for ranked posts",
        "description": "Returns reblog status for posts matching the same criteria as bridge.get_ranked_posts.\nThis is a lightweight endpoint that only returns post identifiers and whether the observer has reblogged each post.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_reblogs(''trending'', '''', ''alice'', 20);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/blog/reblogs?sort=trending&observer=alice&limit=20''`\n",
        "operationId": "hivemind_endpoints.get_reblogs",
        "parameters": [
          {
            "in": "query",
            "name": "sort",
            "required": true,
            "schema": {
              "type": "string",
              "enum": [
                "trending",
                "hot",
                "created",
                "payout",
                "payout_comments",
                "muted"
              ]
            },
            "description": "Sorting method for posts"
          },
          {
            "in": "query",
            "name": "tag",
            "required": false,
            "schema": {
              "type": "string",
              "default": ""
            },
            "description": "Filter by tag, community name, ''my'' for observer''s subscribed communities, or empty/''all'' for all posts\n"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account name to check reblog status for (required)"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 20,
              "minimum": 1
            },
            "description": "Maximum number of posts to return"
          },
          {
            "in": "query",
            "name": "start-author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Author of post to start pagination from"
          },
          {
            "in": "query",
            "name": "start-permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Permlink of post to start pagination from"
          }
        ],
        "responses": {
          "200": {
            "description": "Array of posts with reblog status\n\n* Returns `SETOF hivemind_endpoints.reblog_status`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_reblog_status"
                },
                "example": [
                  {
                    "author": "hiveio",
                    "permlink": "hive-5-celebrating-our-5th-anniversary-as-hive",
                    "reblogged": true
                  },
                  {
                    "author": "alice",
                    "permlink": "my-awesome-post",
                    "reblogged": false
                  }
                ]
              }
            }
          },
          "400": {
            "description": "Invalid parameters (missing observer or invalid sort)"
          }
        }
      }
    },
    "/blog/votes": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get vote status for ranked posts",
        "description": "Returns the observer''s vote on each post matching the same criteria as bridge.get_ranked_posts.\nThis is a lightweight endpoint that only returns post identifiers, whether the observer has voted on each post\nand the percent of that vote, so a front end can cache the anonymous feed and fetch this overlay separately.\nA vote the observer later removed is still reported as `voted` with `vote_percent` 0, as it still appears\nin the post''s active votes.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_votes(''trending'', '''', ''alice'', 20);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/blog/votes?sort=trending&observer=alice&limit=20''`\n",
        "operationId": "hivemind_endpoints.get_votes",
        "parameters": [
          {
            "in": "query",
            "name": "sort",
            "required": true,
            "schema": {
              "type": "string",
              "enum": [
                "trending",
                "hot",
                "created",
                "payout",
                "payout_comments",
                "muted"
              ]
            },
            "description": "Sorting method for posts"
          },
          {
            "in": "query",
            "name": "tag",
            "required": false,
            "schema": {
              "type": "string",
              "default": ""
            },
            "description": "Filter by tag, community name, ''my'' for observer''s subscribed communities, or empty/''all'' for all posts\n"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account name to check vote status for (required)"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 20,
              "minimum": 1
            },
            "description": "Maximum number of posts to return"
          },
          {
            "in": "query",
            "name": "start-author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Author of post to start pagination from"
          },
          {
            "in": "query",
            "name": "start-permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Permlink of post to start pagination from"
          }
        ],
        "responses": {
          "200": {
            "description": "Array of posts with the observer''s vote status\n\n* Returns `SETOF hivemind_endpoints.vote_status`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_vote_status"
                },
                "example": [
                  {
                    "author": "hiveio",
                    "permlink": "hive-5-celebrating-our-5th-anniversary-as-hive",
                    "voted": true,
                    "vote_percent": 10000
                  },
                  {
                    "author": "alice",
                    "permlink": "my-awesome-post",
                    "voted": false,
                    "vote_percent": 0
                  }
                ]
              }
            }
          },
          "400": {
            "description": "Invalid parameters (missing observer or invalid sort)"
          }
        }
      }
    },
    "/posts": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get ranked posts",
        "description": "Returns posts ranked by `sort`, optionally within a tag or community, the same list as\n`bridge.get_ranked_posts`.\n\nTo fetch the next page pass the `author` and `permlink` of the last post of the previous page\nas `start-author` and `start-permlink`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_ranked_posts(''trending'', ''photography'', 20);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/posts?sort=trending&tag=photography&limit=20''`\n",
        "operationId": "hivemind_endpoints.get_ranked_posts",
        "parameters": [
          {
            "in": "query",
            "name": "sort",
            "required": true,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Ranking: `trending`, `hot`, `created`, `payout`, `payout_comments` or `muted`\n"
          },
          {
            "in": "query",
            "name": "tag",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Tag or community name (`hive-NNNNNN`); `my` lists the observer''s communities"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of posts to return, at most the posts-per-call limit (20 unless configured), which is also the default"
          },
          {
            "in": "query",
            "name": "start-author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Author of the last post of the previous page"
          },
          {
            "in": "query",
            "name": "start-permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Permlink of the last post of the previous page"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose mutes and blacklists are applied. The response without an observer\nis the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Ranked posts\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_bridge_post",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unsupported sort, unknown tag or start post, or an invalid parameter"
          }
        }
      }
    },
    "/posts/{author}/{permlink}": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get a post",
        "description": "Returns one post or comment, the same object as `bridge.get_post`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_post(''alice'', ''my-awesome-post'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post''`\n",
        "operationId": "hivemind_endpoints.get_post",
        "parameters": [
          {
            "in": "path",
            "name": "author",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Author of the post"
          },
          {
            "in": "path",
            "name": "permlink",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Permlink of the post"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose mutes and blacklists are applied. The response without an observer\nis the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The post\n\n* Returns `JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.bridge_post",
                  "x-sql-datatype": "JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown or deleted post, or an invalid parameter"
          }
        }
      }
    },
    "/posts/{author}/{permlink}/replies": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get the replies to a post",
        "description": "Returns the posts of `bridge.get_discussion` for the post other than the post itself, as a list\nordered by creation time (ties broken by `author/permlink`), so new replies are added at the end.\nEach reply is the same object as in `bridge.get_discussion`; its `replies` field names its own\ndirect replies. Like `bridge.get_discussion`, only the first 4000 posts of a thread are included.\n\nTo fetch the next page pass the `author` and `permlink` of the last reply of the previous page\nas `start-author` and `start-permlink`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_post_replies(''alice'', ''my-awesome-post'', 20);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/replies?limit=20''`\n",
        "operationId": "hivemind_endpoints.get_post_replies",
        "parameters": [
          {
            "in": "path",
            "name": "author",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Author of the post"
          },
          {
            "in": "path",
            "name": "permlink",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Permlink of the post"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of replies to return, at most the posts-per-call limit (20 unless configured), which is also the default"
          },
          {
            "in": "query",
            "name": "start-author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Author of the last reply of the previous page"
          },
          {
            "in": "query",
            "name": "start-permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Permlink of the last reply of the previous page"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose mutes are applied. The response without an observer\nis the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Replies to the post\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_bridge_post",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown post, a start reply that is not in the discussion, or an invalid parameter"
          }
        }
      }
    },
    "/posts/{author}/{permlink}/votes": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get votes on a post",
        "description": "Returns the votes on one post or comment, in the same order as `database_api.list_votes` with\n`by_comment_voter` (by the voter''s account id, i.e. account creation order).\n\nTo fetch the next page pass the `voter` of the last vote of the previous page as `start-voter`;\nthe page starts after that voter.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_post_votes(''alice'', ''my-awesome-post'', 20);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/posts/alice/my-awesome-post/votes?limit=20''`\n",
        "operationId": "hivemind_endpoints.get_post_votes",
        "parameters": [
          {
            "in": "path",
            "name": "author",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Author of the post"
          },
          {
            "in": "path",
            "name": "permlink",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Permlink of the post"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": 20,
              "minimum": 1
            },
            "description": "Maximum number of votes to return"
          },
          {
            "in": "query",
            "name": "start-voter",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Voter of the last vote of the previous page; the page starts after this voter"
          }
        ],
        "responses": {
          "200": {
            "description": "Votes on the post\n\n* Returns `SETOF hivemind_endpoints.post_vote`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_post_vote"
                },
                "example": [
                  {
                    "voter": "bob",
                    "author": "alice",
                    "permlink": "my-awesome-post",
                    "weight": "1146353766",
                    "rshares": "1879215360",
                    "vote_percent": 10000,
                    "last_update": "2016-09-15T19:47:21",
                    "num_changes": 0
                  }
                ]
              }
            }
          },
          "400": {
            "description": "Unknown post or unknown start voter"
          }
        }
      }
    },
    "/communities": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "List communities",
        "description": "Returns communities ordered by `sort`, optionally only those matching `query`, the same list as\n`bridge.list_communities`.\n\nTo fetch the next page pass the `name` of the last community of the previous page as `last`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_communities(''rank'', NULL, 20);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/communities?sort=rank&limit=20''`\n",
        "operationId": "hivemind_endpoints.get_communities",
        "parameters": [
          {
            "in": "query",
            "name": "sort",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "`rank` (the default), `new` or `subs`"
          },
          {
            "in": "query",
            "name": "query",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Words the community''s title or about text must contain"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of communities to return, at most 100 (the default)"
          },
          {
            "in": "query",
            "name": "last",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Name of the last community of the previous page"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose subscription and role is reported in each community''s `context`. The response\nwithout an observer is the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Communities\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_bridge_community",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unsupported sort, unknown last community, or an invalid parameter"
          }
        }
      }
    },
    "/communities/{name}": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get a community",
        "description": "Returns the community, the same object as `bridge.get_community`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_community(''hive-123456'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/communities/hive-123456''`\n",
        "operationId": "hivemind_endpoints.get_community",
        "parameters": [
          {
            "in": "path",
            "name": "name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Name of the community (`hive-NNNNNN`)"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose subscription and role is reported in `context`. The response\nwithout an observer is the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "The community\n\n* Returns `JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.bridge_community",
                  "x-sql-datatype": "JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown community or an invalid parameter"
          }
        }
      }
    },
    "/communities/{name}/subscribers": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get a community''s subscribers",
        "description": "Returns the community''s subscribers in account name order, the same list as `bridge.list_subscribers`.\nEach row is `[account, role, title, subscribed_at]`.\n\nTo fetch the next page pass the account name of the last row of the previous page as `last`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_community_subscribers(''hive-123456'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/communities/hive-123456/subscribers?limit=100''`\n",
        "operationId": "hivemind_endpoints.get_community_subscribers",
        "parameters": [
          {
            "in": "path",
            "name": "name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Name of the community (`hive-NNNNNN`)"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of rows to return, at most 100 (the default)"
          },
          {
            "in": "query",
            "name": "last",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account of the last subscriber of the previous page"
          }
        ],
        "responses": {
          "200": {
            "description": "Get a community''s subscribers\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_string_tuple",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown community, a last account that is not subscribed, or an invalid parameter"
          }
        }
      }
    },
    "/communities/{name}/roles": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get a community''s roles",
        "description": "Returns the community''s accounts that have a role other than guest, highest role first, the same list as `bridge.list_community_roles`.\nEach row is `[account, role, title]`.\n\nTo fetch the next page pass the account name of the last row of the previous page as `last`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_community_roles(''hive-123456'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/communities/hive-123456/roles?limit=50''`\n",
        "operationId": "hivemind_endpoints.get_community_roles",
        "parameters": [
          {
            "in": "path",
            "name": "name",
            "required": true,
            "schema": {
              "type": "string"
            },
            "description": "Name of the community (`hive-NNNNNN`)"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of rows to return, at most 1000 (the default)"
          },
          {
            "in": "query",
            "name": "last",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account of the last row of the previous page"
          }
        ],
        "responses": {
          "200": {
            "description": "Get a community''s roles\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_string_tuple",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unknown community or last account, or an invalid parameter"
          }
        }
      }
    },
    "/search/posts": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Search posts",
        "description": "Returns the posts and comments matching the full-text query `q`, the same list as\n`search-api.find_text`. Needs the `pg_search` extension.\n\nTo fetch the next page pass the `author` and `permlink` of the last post of the previous page\nas `start-author` and `start-permlink`.\n\nSQL example\n* `SELECT hivemind_endpoints.search_posts(''beekeeping'', ''relevance'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/search/posts?q=beekeeping&sort=relevance&limit=20''`\n",
        "operationId": "hivemind_endpoints.search_posts",
        "parameters": [
          {
            "in": "query",
            "name": "q",
            "required": true,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Search query; supports quoted phrases, `+`/`-` terms and field prefixes as `search-api.find_text` does\n"
          },
          {
            "in": "query",
            "name": "sort",
            "required": true,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "`relevance` or `created`"
          },
          {
            "in": "query",
            "name": "author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Only posts by this account"
          },
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of posts to return, at most the posts-per-call limit (20 unless configured), which is also the default"
          },
          {
            "in": "query",
            "name": "start-author",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Author of the last post of the previous page"
          },
          {
            "in": "query",
            "name": "start-permlink",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Permlink of the last post of the previous page"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Account whose mutes are applied. The response without an observer\nis the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Matching posts\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_bridge_post",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "Unsupported sort, unknown account or start post, an invalid parameter, or no full-text search"
          }
        }
      }
    },
    "/tags/trending": {
      "get": {
        "tags": [
          "blog_api"
        ],
        "summary": "Get trending topics",
        "description": "Returns the trending communities and tags, the same list as `bridge.get_trending_topics`.\nEach row is `[name, title]`.\n\nSQL example\n* `SELECT hivemind_endpoints.get_trending_tags(10);`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/tags/trending?limit=10''`\n",
        "operationId": "hivemind_endpoints.get_trending_tags",
        "parameters": [
          {
            "in": "query",
            "name": "limit",
            "required": false,
            "schema": {
              "type": "integer",
              "default": null
            },
            "description": "Maximum number of topics to return, at most 25 (the default)"
          },
          {
            "in": "query",
            "name": "observer",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "Accepted for parity with `bridge.get_trending_topics`. The response without an observer\nis the one meant for caching.\n"
          }
        ],
        "responses": {
          "200": {
            "description": "Trending topics\n\n* Returns `SETOF JSONB`\n",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/hivemind_endpoints.array_of_string_tuple",
                  "x-sql-datatype": "SETOF JSONB"
                }
              }
            }
          },
          "400": {
            "description": "An invalid parameter"
          }
        }
      }
    },
    "/sync-status": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Get hivemind''s sync status",
        "description": "Get the last block processed by hivemind as an object containing both\nthe block number and its timestamp (UTC). This is the uniform HAF-app\nsync/health endpoint: the timestamp lets a consumer compute staleness\nwith a single call (`age = now() - last_block_time`) without needing a\nseparate head-block reference.\n`last_block_time` is null if no block has been processed yet.\nWhile the HAF instance is still in massive sync (indexes not yet\nbuilt) the call fails fast with an error rather than executing an\nunindexed lookup.\n\nSQL example\n* `SELECT hivemind_endpoints.get_sync_status();`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/sync-status''`\n",
        "operationId": "hivemind_endpoints.get_sync_status",
        "responses": {
          "200": {
            "description": "Last block processed by hivemind and its timestamp.\n\n* Returns `JSON`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "x-sql-datatype": "JSON",
                  "properties": {
                    "last_block_num": {
                      "type": "integer",
                      "description": "highest block number processed by hivemind"
                    },
                    "last_block_time": {
                      "type": "string",
                      "format": "date-time",
                      "description": "UTC timestamp of that block"
                    }
                  }
                },
                "example": {
                  "last_block_num": 5000000,
                  "last_block_time": "2016-09-15T19:47:21"
                }
              }
            }
          }
        }
      }
    },
    "/version": {
      "get": {
        "tags": [
          "Other"
        ],
        "summary": "Get hivemind''s version",
        "description": "Get the version and git revision of the running hivemind, together with\nthe database schema version (patch level). The fields match the ones\nreturned by the JSON-RPC `hive.get_info` call.\n\nSQL example\n* `SELECT hivemind_endpoints.get_version();`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/version''`\n",
        "operationId": "hivemind_endpoints.get_version",
        "responses": {
          "200": {
            "description": "Hivemind version information.\n\n* Returns `JSON`\n",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "x-sql-datatype": "JSON",
                  "properties": {
                    "hivemind_version": {
                      "type": "string",
                      "description": "hivemind package version"
                    },
                    "hivemind_git_rev": {
                      "type": "string",
                      "description": "git commit hash hivemind was built from"
                    },
                    "hivemind_git_date": {
                      "type": "string",
                      "format": "date-time",
                      "description": "date of that git commit"
                    },
                    "database_schema_version": {
                      "type": "integer",
                      "description": "database schema patch level"
                    }
                  }
                },
                "example": {
                  "hivemind_version": "1.28.8",
                  "hivemind_git_rev": "455898cc3462d4e5ee2274756e5e3d44688fe204",
                  "hivemind_git_date": "2026-10-01T12:00:00",
                  "database_schema_version": 42
                }
              }
            }
          }
        }
      }
    }
  }
}
$$;
-- openapi-generated-code-end
begin
  return openapi;
end
$_$ language plpgsql;'
, __swagger_url);

END
$__$;
