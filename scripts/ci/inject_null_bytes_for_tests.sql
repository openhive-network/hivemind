-- Null byte injection test - SKIPPED for body_value (JSONB) schema.
--
-- Previously, HAF stored operation bodies in body_binary (a custom type that
-- could carry arbitrary bytes including \u0000). Hivemind needed to handle
-- null bytes during indexing since real blockchain data contains them
-- (e.g., block 104130768, guest4test has \u0000 in json_metadata).
--
-- With the body_value migration, HAF now stores operations as JSONB, which
-- fundamentally cannot contain null bytes (PostgreSQL rejects \u0000 in JSONB).
-- HAF strips null bytes before insertion, so they never reach hivemind.
-- This test is therefore no longer applicable.

DO $$
BEGIN
    RAISE NOTICE 'Null byte injection SKIPPED: body_value (JSONB) cannot contain \u0000 — HAF strips them before insertion';
END;
$$;
