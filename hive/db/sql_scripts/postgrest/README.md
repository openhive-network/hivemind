After converting methods to SQL, some changed the way they report errors. These tests are marked with the `postgrest_ignore` tag because they are enabled on the Python server but should not be run on the PostgREST server.

There are also modified copies of the `postgrest_ignore` tests, marked with the `postgrest_exception` tag, which are adapted to handle and test SQL exceptions. These tests are located in the directory: hivemind/tests/api_tests/hivemind/tavern/postgrest_negative/.

## Optional lite_posts serving intercept

`hivemind_postgrest_utilities.dispatch` can hand a request to the lite_posts HAF app before its own routing. This is off unless the placeholder setting `hivemind.lite_intercept` reads `on`; hivemind never sets it, so a stock install, CI and every node without lite_posts behave exactly as before, at the cost of one `current_setting` call per request.

Installing lite_posts on a node is the operator's choice to let it change the output of selected stock `bridge.*` / `condenser_api.*` methods and to add the `lite.*` methods there. Its installer turns the intercept on with:

    ALTER DATABASE <db> SET hivemind.lite_intercept = 'on';

and the operator turns it off with `ALTER DATABASE <db> RESET hivemind.lite_intercept;` (new sessions pick either up).

With the setting on, `dispatch` calls `lite_posts.intercept(api_type TEXT, method_type TEXT, params JSONB) RETURNS JSONB`, which lite_posts owns:

- it returns NULL for every (api, method) it does not handle, and dispatch continues to hivemind's own method, so unhandled calls, including hivemind's own errors (an unknown api is still "Api not found"), are unchanged;
- otherwise it returns the `result` value of the JSON-RPC response;
- it reports errors by raising through the `hivemind_postgrest_utilities.raise_*` helpers, so `hivemind_endpoints.home` shapes them like hivemind's own errors.

The call is resolved at run time, so hivemind installs with or without the `lite_posts` schema. With the setting on and the function missing, every request fails with "function lite_posts.intercept(...) does not exist"; the lite_posts installer must not leave a node in that state.

`tests/sql/dispatch_lite_intercept.sql` checks this contract against a stub `lite_posts.intercept`.
