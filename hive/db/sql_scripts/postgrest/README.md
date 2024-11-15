After converting methods to SQL, some changed the way they report errors. These tests are marked with the `postgrest_ignore` tag because they are enabled on the Python server but should not be run on the PostgREST server.

There are also modified copies of the `postgrest_ignore` tests, marked with the `postgrest_exception` tag, which are adapted to handle and test SQL exceptions. These tests are located in the directory: hivemind/tests/api_tests/hivemind/tavern/postgrest_negative/.
