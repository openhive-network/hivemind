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
  version: 1.27.11
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
'create or replace function hivemind_endpoints.root() returns json as $_$
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
    "version": "1.27.11"
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
            "type": "string",
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
          "operations_result": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/hivemind_endpoints.operation"
            },
            "description": "List of operation results"
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
        "description": "List the operations in reversed order (first page is the oldest) for given account. \nThe page size determines the number of operations per page.\n\nSQL example\n* `SELECT * FROM hivemind_endpoints.get_ops_by_account(''blocktrades'');`\n\nREST call example\n* `GET ''https://%1$s/hivemind-api/accounts/blocktrades/operations?page-size=3''`\n",
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
            "name": "operation-types",
            "required": false,
            "schema": {
              "type": "string",
              "default": null
            },
            "description": "List of operation types to get. If NULL, gets all operation types.\nexample: `18,12`\n"
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
                    },
                    {
                      "op": {
                        "type": "producer_reward_operation",
                        "value": {
                          "producer": "blocktrades",
                          "vesting_shares": {
                            "nai": "@@000000037",
                            "amount": "3003850165",
                            "precision": 6
                          }
                        }
                      },
                      "block": 4999992,
                      "trx_id": null,
                      "op_pos": 1,
                      "op_type_id": 64,
                      "timestamp": "2016-09-15T19:46:57",
                      "virtual_op": true,
                      "operation_id": "21474802120262208",
                      "trx_in_block": -1
                    },
                    {
                      "op": {
                        "type": "producer_reward_operation",
                        "value": {
                          "producer": "blocktrades",
                          "vesting_shares": {
                            "nai": "@@000000037",
                            "amount": "3003868105",
                            "precision": 6
                          }
                        }
                      },
                      "block": 4999959,
                      "trx_id": null,
                      "op_pos": 1,
                      "op_type_id": 64,
                      "timestamp": "2016-09-15T19:45:12",
                      "virtual_op": true,
                      "operation_id": "21474660386343488",
                      "trx_in_block": -1
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
