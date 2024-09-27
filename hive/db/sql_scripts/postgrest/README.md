Each method is tested on the PostgREST server (CI job e2e_benchmark_on_postgrest). Tests for completed methods are marked with `postgrest_ready`.

After converting methods to SQL, some changed the way they report errors. These tests are marked with the `never_postgrest` tag because they are enabled on the Python server but should not be run on the PostgREST server.

There are also modified copies of the `never_postgrest` tests, marked with the `postgrest_exception` tag, which are adapted to handle and test SQL exceptions. These tests are located in the directory: hivemind/tests/api_tests/hivemind/tavern/postgrest_negative/.
