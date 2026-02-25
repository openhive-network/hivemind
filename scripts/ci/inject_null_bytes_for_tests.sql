-- Inject \u0000 null byte escape sequences into mock HAF operation data.
--
-- PostgreSQL JSONB rejects \u0000, so we cannot include it in mock JSON files.
-- Instead, we update already-inserted operations using direct text-to-hafd.operation
-- cast, which goes through the Hive C serializer and preserves \u0000 in binary form.
--
-- This simulates real blockchain data (e.g., block 104130768, guest4test) where
-- json_metadata contains \u0000 escape sequences.

-- Update the comment_operation for nulltester to include \u0000 in json_metadata
UPDATE hafd.operations
SET body_binary = '{"type":"comment_operation","value":{"parent_author":"","parent_permlink":"test","author":"nulltester","permlink":"null-byte-post","title":"Title for null byte test","body":"Body for null byte defense test post","json_metadata":"{\"tags\":[\"test\"],\"app\":\"test\u0000app\"}"}}'::hafd.operation
WHERE body_binary::text LIKE '%nulltester%'
  AND body_binary::text LIKE '%null-byte-post%'
  AND body_binary::text LIKE '%comment_operation%';

-- Update the account_update2_operation for nulltester to include \u0000 in metadata
UPDATE hafd.operations
SET body_binary = '{"type":"account_update2_operation","value":{"account":"nulltester","json_metadata":"{\"profile\":{\"name\":\"nulltester\",\"about\":\"about null\u0000tester\",\"website\":\"https://example.com\",\"profile_image\":\"\",\"cover_image\":\"\",\"location\":\"\"}}","posting_json_metadata":"{\"profile\":{\"name\":\"nulltester posting\",\"about\":\"posting about null\u0000tester\",\"website\":\"https://example.com\",\"profile_image\":\"\",\"cover_image\":\"\",\"location\":\"\"}}","extensions":[]}}'::hafd.operation
WHERE body_binary::text LIKE '%nulltester%'
  AND body_binary::text LIKE '%account_update2_operation%';
