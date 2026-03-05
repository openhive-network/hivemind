-- Inject null bytes into mock HAF operation binary data for testing.
--
-- The Hive C serializer (_operation_in) normalizes \u0000 during JSON parsing,
-- so we cannot inject null bytes via JSON text. Instead, we manipulate the raw
-- bytea representation: find the target byte sequence in the binary, splice in
-- a \x00 byte, fix the enclosing string length prefix, and write back.
--
-- This simulates real blockchain data (e.g., block 104130768, guest4test)
-- where json_metadata contains null bytes in the binary representation.
--
-- In Hive protocol, strings are encoded as: varint_length + raw_bytes.
-- The json_metadata field contains {"tags":["test"],"app":"testapp"} (32 bytes).
-- We change "testapp" -> "test\x00app" making it 33 bytes, and update the length.

DO $$
DECLARE
    _bin bytea;
    _id bigint;
    _testapp_pos int;
    _meta_start_pos int;
    _old_len_byte int;
    _result bytea;
    _verify_text text;
    _pg_major int;
BEGIN
    -- Skip null byte injection on PostgreSQL 18+ where it corrupts JSONB wire serialization
    _pg_major := current_setting('server_version_num')::int / 10000;
    IF _pg_major >= 18 THEN
        RAISE NOTICE 'Skipping null byte injection on PostgreSQL % (PG18+ incompatible)', current_setting('server_version');
        RETURN;
    END IF;
    -- Find the comment_operation for nulltester
    -- Note: body_binary::text outputs bytea hex, not JSON.
    -- Use operation_to_jsontext() to get the JSON representation.
    SELECT ho.id, ho.body_binary::bytea
    INTO _id, _bin
    FROM hafd.operations ho
    WHERE hafd.operation_to_jsontext(ho.body_binary) LIKE '%nulltester%'
      AND hafd.operation_to_jsontext(ho.body_binary) LIKE '%null-byte-post%';

    IF _id IS NULL THEN
        RAISE EXCEPTION 'null byte injection: comment_operation for nulltester not found';
    END IF;

    RAISE NOTICE 'Found comment_operation for nulltester, id=%', _id;

    -- Find 'testapp' in the bytea (ASCII: 0x74 65 73 74 61 70 70)
    _testapp_pos := position(convert_to('testapp', 'UTF8') in _bin);
    IF _testapp_pos = 0 THEN
        RAISE EXCEPTION 'null byte injection: "testapp" bytes not found in operation binary';
    END IF;
    RAISE NOTICE 'Found "testapp" at byte position %', _testapp_pos;

    -- Replace 'testapp' (7 bytes) with 'test' + \x00 + 'app' (8 bytes)
    _result := substring(_bin from 1 for _testapp_pos + 3)  -- up to and including 'test'
            || E'\\x00'::bytea                                -- null byte
            || substring(_bin from _testapp_pos + 4);         -- 'app' onwards

    -- Now fix the json_metadata string varint length prefix.
    -- The json_metadata content starts with '{"tags":' (ASCII).
    -- The varint length byte is immediately before this content.
    _meta_start_pos := position(convert_to('{"tags":', 'UTF8') in _result);
    IF _meta_start_pos = 0 THEN
        RAISE EXCEPTION 'null byte injection: json_metadata content marker not found';
    END IF;

    -- The length byte is at position (_meta_start_pos - 1) in 1-indexed,
    -- which is (_meta_start_pos - 2) in 0-indexed (for get_byte/set_byte)
    _old_len_byte := get_byte(_result, _meta_start_pos - 2);
    RAISE NOTICE 'json_metadata length byte at 0-indexed position %, value: %', _meta_start_pos - 2, _old_len_byte;

    -- Increment length by 1 (we added 1 byte)
    _result := set_byte(_result, _meta_start_pos - 2, _old_len_byte + 1);
    RAISE NOTICE 'Updated json_metadata length to %', _old_len_byte + 1;

    -- Write back via bytea -> hafd.operation implicit cast
    UPDATE hafd.operations
    SET body_binary = _result::hafd.operation
    WHERE id = _id;

    -- Verify: read back using operation_to_jsontext and check for \u0000
    SELECT hafd.operation_to_jsontext(ho.body_binary) INTO _verify_text
    FROM hafd.operations ho WHERE ho.id = _id;

    IF _verify_text LIKE '%\u0000%' THEN
        RAISE NOTICE 'null byte injection SUCCESS: \u0000 found in operation_to_jsontext output (id=%)', _id;
    ELSE
        RAISE NOTICE 'Verify text (first 300 chars): %', substring(_verify_text from 1 for 300);
        RAISE EXCEPTION 'null byte injection FAILED: \u0000 not found after bytea manipulation';
    END IF;

    -- Also verify through the ::jsonb cast path (used by operations_view)
    -- This tells us whether _operation_to_jsonb() preserves the null byte.
    DECLARE
        _jsonb_text text;
        _jsonb_val jsonb;
    BEGIN
        SELECT ho.body_binary::jsonb INTO _jsonb_val
        FROM hafd.operations ho WHERE ho.id = _id;

        _jsonb_text := _jsonb_val::text;
        RAISE NOTICE 'body_binary::jsonb cast succeeded';
        RAISE NOTICE 'JSONB text (first 300 chars): %', substring(_jsonb_text from 1 for 300);

        IF _jsonb_text LIKE '%\u0000%' THEN
            RAISE NOTICE 'JSONB PATH: \u0000 PRESERVED in body_binary::jsonb (null byte will reach load_ops_staging)';
        ELSE
            RAISE NOTICE 'JSONB PATH: \u0000 LOST during body_binary::jsonb cast (C-level _operation_to_jsonb drops it)';
            RAISE NOTICE 'The ::jsonb cast path strips null bytes - sync will NOT crash even without the REPLACE fix';
            RAISE NOTICE 'Testing must target the output/API path instead (PostgREST functions that cast TEXT to ::jsonb)';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'body_binary::jsonb cast FAILED with: %', SQLERRM;
        RAISE NOTICE 'This means _operation_to_jsonb() rejects null bytes - they cannot enter via this path';
    END;
END;
$$;
