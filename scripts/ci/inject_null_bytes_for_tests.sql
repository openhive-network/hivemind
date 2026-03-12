-- Inject null bytes into mock HAF operation JSONB data for testing.
--
-- With body_value (JSONB), we directly manipulate the json_metadata field
-- to contain a \u0000 sequence. This simulates real blockchain data
-- (e.g., block 104130768, guest4test) where json_metadata contains null bytes.
--
-- The json_metadata field contains {"tags":["test"],"app":"testapp"}.
-- We change "testapp" -> "test\u0000app" by rebuilding the inner JSON.

DO $$
DECLARE
    _id bigint;
    _body_val jsonb;
    _meta_text text;
    _new_meta text;
    _new_meta_jsonb jsonb;
    _verify_text text;
    _pg_major int;
BEGIN
    -- Skip null byte injection on PostgreSQL 18+ where it corrupts JSONB wire serialization
    _pg_major := current_setting('server_version_num')::int / 10000;
    IF _pg_major >= 18 THEN
        RAISE NOTICE 'Skipping null byte injection on PostgreSQL % (PG18+ incompatible)', current_setting('server_version');
        RETURN;
    END IF;

    -- Find the comment_operation for nulltester using body_value (JSONB)
    SELECT ho.id, ho.body_value
    INTO _id, _body_val
    FROM hafd.operations ho
    WHERE ho.body_value->>'author' = 'nulltester'
      AND ho.body_value->>'permlink' = 'null-byte-post';

    IF _id IS NULL THEN
        RAISE EXCEPTION 'null byte injection: comment_operation for nulltester not found';
    END IF;

    RAISE NOTICE 'Found comment_operation for nulltester, id=%', _id;

    -- Extract json_metadata, inject null byte into "testapp" -> "test\u0000app"
    _meta_text := _body_val->>'json_metadata';
    IF _meta_text IS NULL OR _meta_text = '' THEN
        RAISE EXCEPTION 'null byte injection: json_metadata is empty or null';
    END IF;

    IF position('testapp' in _meta_text) = 0 THEN
        RAISE EXCEPTION 'null byte injection: "testapp" not found in json_metadata: %', _meta_text;
    END IF;

    RAISE NOTICE 'Original json_metadata: %', _meta_text;

    -- Replace 'testapp' with 'test\u0000app' (literal \u0000 in the string)
    _new_meta := replace(_meta_text, 'testapp', E'test\u0000app');

    RAISE NOTICE 'Modified json_metadata (first 100 chars): %', substring(_new_meta from 1 for 100);

    -- Update body_value with the modified json_metadata
    -- Use jsonb_set to replace the json_metadata field value
    UPDATE hafd.operations
    SET body_value = jsonb_set(body_value, '{json_metadata}', to_jsonb(_new_meta))
    WHERE id = _id;

    -- Verify: read back and check for \u0000
    SELECT ho.body_value->>'json_metadata' INTO _verify_text
    FROM hafd.operations ho WHERE ho.id = _id;

    IF _verify_text LIKE E'%\u0000%' THEN
        RAISE NOTICE 'null byte injection SUCCESS: \u0000 found in body_value json_metadata (id=%)', _id;
    ELSE
        RAISE NOTICE 'Verify text (first 300 chars): %', substring(_verify_text from 1 for 300);
        RAISE EXCEPTION 'null byte injection FAILED: \u0000 not found after JSONB manipulation';
    END IF;

    -- Verify through the body_value::text path
    DECLARE
        _jsonb_text text;
    BEGIN
        SELECT ho.body_value::text INTO _jsonb_text
        FROM hafd.operations ho WHERE ho.id = _id;

        RAISE NOTICE 'body_value::text (first 300 chars): %', substring(_jsonb_text from 1 for 300);

        IF _jsonb_text LIKE E'%\\u0000%' THEN
            RAISE NOTICE 'JSONB PATH: \u0000 PRESERVED in body_value (null byte will reach load_ops_staging)';
        ELSE
            RAISE NOTICE 'JSONB PATH: \u0000 LOST in body_value::text rendering';
            RAISE NOTICE 'Testing must target the output/API path instead';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'body_value verification FAILED with: %', SQLERRM;
    END;
END;
$$;
