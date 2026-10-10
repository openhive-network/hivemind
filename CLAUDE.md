# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Hivemind** is a HAF (Hive Application Framework)-based microservice that provides social media features for the Hive blockchain. It consists of two main components:

1. **Indexer** (Python): Extracts and processes social data from HAF into application tables
2. **Server** (PL/pgSQL + PostgREST): Exposes a JSON-RPC API for querying social data

The project is transitioning from Python to PL/pgSQL, so you'll find remnants of old code patterns.

## Development Commands

### Environment Setup

**Prerequisites:** Python 3.10+, PostgreSQL 17+, pip >= 22.2.2, setuptools >= 63.1.0

```bash
# Clone with submodules (HAF and reputation_tracker are submodules)
git clone --recurse-submodules https://gitlab.syncad.com/hive/hivemind.git

# Install in virtual environment (RECOMMENDED)
python3 -m venv venv/
. venv/bin/activate
pip install .                    # Base install
pip install .'[dev]'            # With dev tools (ruff, pyYAML)
pip install .'[tests]'          # With testing tools (tox)

# Deactivate virtual environment
deactivate
```

### Building and Running

**Docker Images:**
```bash
# Build HAF (from haf/ submodule)
cd haf
./scripts/ci-helpers/build_instance.sh local $(pwd) registry.gitlab.syncad.com/hive/haf

# Build reputation tracker (from reputation_tracker/ submodule)
cd reputation_tracker
docker build -t registry.gitlab.syncad.com/hive/reputation_tracker:local .

# Build Hivemind
./scripts/ci-helpers/build_instance.sh local $(pwd) registry.gitlab.syncad.com/hive/hivemind

# Build postgrest-rewriter (Nginx)
docker build -t postgrest_rewriter:local -f Dockerfile.rewriter .
```

**Installation on HAF Database:**
```bash
# 1. Setup roles and schema
./scripts/setup_postgres.sh --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log

# 2. Install reputation_tracker (required dependency)
./reputation_tracker/scripts/install_app.sh \
  --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log \
  --schema=reptracker_app \
  --is_forking="false"

# 3. Install Hivemind
./scripts/install_app.sh --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log
```

**Running the Indexer:**
```bash
# Activate virtual environment first
. venv/bin/activate

# Full sync to head block
hive sync \
  --reptracker-schema-name=reptracker_app \
  --database-url=postgresql://hivemind@localhost:5432/haf_block_log

# Sync to specific block (for testing - creates indexes at end)
hive sync \
  --reptracker-schema-name=reptracker_app \
  --test-max-block=5000000 \
  --database-url=postgresql://hivemind@localhost:5432/haf_block_log

# Check available options
hive sync --help
```

**Running the Server:**
```bash
# Start PostgREST server (requires openresty/nginx rewriter)
./scripts/start_postgrest.sh

# Or start openresty separately if installed on host
sudo /etc/init.d/openresty start

# Test the API
curl localhost:8080 \
  --header "Content-Type: application/json" \
  --data '{"id": "test", "method": "condenser_api.get_follow_count", "params": ["gtg"], "jsonrpc": "2.0"}'
```

### Testing

**API Tests (Tavern framework):**
```bash
# Run all API tests
./scripts/run_tests.sh

# Run specific test group (from project root)
./scripts/ci/start-api-smoketest.sh \
  localhost 8080 \
  bridge_api_patterns/get_ranked_posts/ \
  api_smoketest_bridge.xml

# Using tox directly (set environment first)
export HIVEMIND_ADDRESS="localhost"
export HIVEMIND_PORT="8080"
export TAVERN_DIR="$(realpath ./tests/api_tests/hivemind/tavern)"
tox -e tavern -- -W ignore::pytest.PytestDeprecationWarning -n auto --junitxml=results.xml bridge_api_patterns/
```

**Unit Tests:**
```bash
# All tests
make test-all
# or: py.test --cov=hive --capture=sys

# Specific test suites
make test-utils     # Utils tests
make test-server    # Server tests
```

**Test Setup with Mock Data:**

For comprehensive testing, you need HAF synced to 5M blocks + injected mock operations:

```bash
# 1. Start HAF to 5M blocks (requires block_log with 5M+ blocks)
docker run -d -e PG_ACCESS="host haf_block_log all 0.0.0.0/0 trust" \
  --network=haf --name=haf \
  registry.gitlab.syncad.com/hive/haf/minimal-instance:local \
  --replay --stop-at-block=5000000

# 2. Inject mock data (Docker method - includes reputation_tracker + hafah)
docker run --rm --network=haf --name=hivemind \
  registry.gitlab.syncad.com/hive/hivemind/instance:local \
  setup --database-admin-url=postgresql://haf_admin@haf:5432/haf_block_log \
  --with-apps --add-mocks="true"

# 3. Sync reputation_tracker to 4,999,979
docker run --rm --network=haf --name=hivemind \
  --entrypoint=./app/reputation_tracker/scripts/process_blocks.sh \
  registry.gitlab.syncad.com/hive/hivemind/instance:local \
  --stop-at-block=4999979 --postgres-url="postgresql://haf_admin@haf/haf_block_log"

# 4. Sync Hivemind to 5,000,024 (with community-start-block for testing)
docker run --rm --network=haf --name=hivemind \
  registry.gitlab.syncad.com/hive/hivemind/instance:local \
  sync --test-max-block=5000024 --community-start-block=4998000 \
  --database-url=postgresql://hivemind@haf/haf_block_log

# 5. Finish syncing reputation_tracker
docker run --rm --network=haf --name=hivemind \
  --entrypoint=./app/reputation_tracker/scripts/process_blocks.sh \
  registry.gitlab.syncad.com/hive/hivemind/instance:local \
  --stop-at-block=5000024 --postgres-url="postgresql://haf_admin@haf/haf_block_log"

# 6. Start server and run tests (see API Tests section above)
```

### Code Formatting

**ALWAYS run ruff before committing Python code:**
```bash
cd <repo_root>
pip install .'[dev]'  # If not already installed
ruff check --fix hive/   # Lint and auto-fix issues
ruff format hive/        # Format all Python in hive/
ruff format <file.py>    # Format specific file
```

### Uninstalling

```bash
# Uninstall Hivemind from HAF database
./scripts/uninstall_app.sh --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log
```

## Architecture Overview

### Directory Structure

```
hive/                      # Main Python package
├── cli.py                 # Entry point - routes commands (sync, build_schema, status)
├── conf.py                # CLI argument parsing and configuration
├── db/
│   ├── schema.py          # Schema setup routines and SQL script loader
│   ├── adapter.py         # Database connection management
│   ├── sql_scripts/       # Pure SQL code
│   │   └── postgrest/     # Server-side SQL functions (PL/pgSQL)
│   └── db_state.py        # Database state management
├── indexer/               # Block processing and data extraction
│   ├── sync.py            # Main sync loop (SyncHiveDb class)
│   ├── blocks.py          # Block processing coordination
│   ├── posts.py           # Post indexing
│   ├── accounts.py        # Account data
│   ├── community.py       # Community operations
│   ├── follow.py          # Follow/unfollow operations
│   ├── votes.py           # Vote processing
│   ├── notify.py          # Notification generation
│   ├── hive_db/           # HAF-specific data providers
│   └── mocking/           # Mock data injection for testing
└── utils/                 # Utility functions

docker/                    # Docker entrypoints
scripts/                   # Shell scripts for setup/deployment
├── install_app.sh         # Install Hivemind to HAF
├── uninstall_app.sh       # Remove Hivemind from HAF
├── setup_postgres.sh      # Create roles and schemas
├── start_postgrest.sh     # Start PostgREST server
└── ci/                    # CI-specific scripts

tests/
├── api_tests/hivemind/tavern/  # Tavern YAML test definitions
│   ├── bridge_api_patterns/    # Bridge API tests
│   ├── condenser_api_patterns/ # Condenser API tests
│   └── postgrest_negative/     # Negative test cases
└── utils/                      # Python unit tests

haf/                       # HAF submodule (Hive Application Framework)
reputation_tracker/        # Reputation tracker submodule (required dependency)
hafah/                     # HAfAH submodule (account history application)
mock_data/                 # Mock block/vops data for testing
```

### Key Concepts

**Three Sync Stages:**

The indexer operates in three modes for efficiency:

1. **MASSIVE_WITHOUT_INDEXES**: Initial sync, 1000-block batches, no indexes (maximum speed)
2. **MASSIVE_WITH_INDEXES**: Continue batches with indexes enabled (faster lookups)
3. **LIVE**: Near head block, process blocks one at a time as produced

Indexes are created when transitioning from massive to live sync (or when hitting `--test-max-block`).

**HAF Context:**
- Hivemind uses the `hivemind_app` context/schema
- Only processes irreversible blocks (no micro-fork handling needed)
- Depends on `reputation_tracker` application (default schema: `reptracker_app`)

**Database Schemas:**
- `hivemind_app`: Application tables with social data
- `hivemind_endpoints`: Server functions called by PostgREST
- `hivemind_postgrest_utilities`: Utilities for endpoints

**Database Roles:**
- `hivemind`: Used for running sync and server

**Server Architecture:**
- PostgREST exposes PostgreSQL functions as REST endpoints
- Nginx/openresty rewrites JSON-RPC calls to `/rpc/home` endpoint
- All API logic is in PL/pgSQL functions in `hive/db/sql_scripts/postgrest/`

**Entry Points (setup.cfg):**
- `hive`: Main CLI (routes to sync, build_schema, upgrade_schema, status)
- `mocker`: Inject mock data into HAF for testing

**Dependencies (Python):**
- psycopg2 for direct PostgreSQL access
- configargparse for configuration
- psycopg2-binary for PostgreSQL

**Testing Framework:**
- Tavern (pytest plugin) for API tests (YAML-based)
- Tests are in `tests/api_tests/hivemind/tavern/`
- Run via tox with `-e tavern`

**Tavern Test Pattern Files:**
- Each test has a `.tavern.yaml` file and a corresponding `.pat.json` pattern file
- Pattern files contain expected JSON responses that tests compare against
- When tests run, `.out.json` files are generated with actual API output
- Output files are available as artifacts in the `e2e_benchmark_on_postgrest` CI job
- Download artifacts to `logs/tavern/<api_type>/<test_name>/<test>.out.json`
- Use these `.out.json` files to see actual API responses and fix pattern mismatches

**Tests that need real data:**

A positive test's values come from CI's mock-data database (HAF replayed to 5M blocks + mocks + a
hivemind sync), which an AIDEV session doesn't have. Don't invent them, and don't derive them from
other patterns unless only the shape changes. Instead:

1. Commit the new `*.tavern.yaml` with a `{}` placeholder `.pat.json`. CI fails such a test until it is filled.
2. Run `scripts/ci/generate_patterns.py <test>.tavern.yaml ...` (or `--all-placeholders`; `--dry-run` first
   shows the branch, pipeline variables and tests). It pushes HEAD to `patterns/<shortsha>` with `-o ci.skip`,
   runs a pipeline there on a cached sync (`POSTGREST_ONLY_CHANGE=true AUTO_SKIP_SYNC=false`), copies each
   test's `.out.json` from `e2e_benchmark_on_postgrest`'s artifacts to its `.pat.json`, prints a per-test summary
   (keys, list lengths, nulls) and deletes the branch. It never overwrites a non-placeholder pattern without `--force`.
   `--artifacts <dir|zip>` applies artifacts already downloaded.
3. Check each value against independent data before committing the patterns. `MISSING` means no `.out.json`:
   the test passed against `{}` (e.g. an empty discussion, a real `{}` answer) or did not run.

The script needs `GITLAB_TOKEN` and push access to gitlab.syncad.com, which an implementing agent doesn't have.
In an AIDEV workflow, commit the placeholders and say in the summary which tests need patterns; an operator runs
the script after the workflow (or in a follow-up issue the agent requests).

**Tavern under AIDEV (the `tavern` step of the `full` slot):**
- Runs the same groups as `e2e_benchmark_on_postgrest`, against a per-run clone of the shared synced hivemind. That fixture is HAF 5M + CI's mocks + a hivemind sync to 5000024, with templates keyed by (schema revision, sync recipe), hosted by the `hivemind-shared` session (`sandbox.shared.hivemind`, `.aidev/shared-hivemind/`).
- The tree's PostgREST SQL is reloaded into the clone first, so endpoint/query changes are tested without a re-sync.
- The schema revision is the last hash in `hive/db/sql_scripts/upgrade/update_db_patchlevel.sql`; the sync recipe hashes the mocks, the indexer, the non-PostgREST SQL, the app submodule commits, `seed.sh` and the HAF commit (`.aidev/shared-hivemind/shared_fixture.py`). When no template matches the revision (a schema/indexer change), the step skips with `no hivemind fixture for schema revision <rev>; seeding requested`. When only the recipe misses, it runs against the revision's newest template with an `advisory:` line naming both recipes. Either way the provider seeds the exact key from the pushed commit for a later run.
- To add or refresh a pattern: run `aidev test run --slot full`, read the actual response from `test-results/full/tavern-out/<group>/…/<test>.out.json`, and copy it over the `.pat.json` once it is right. Then rerun until `test-results/full/tavern-<group>.xml` passes.
- Details: `.aidev/README.md`, "The `tavern` step" and "The shared synced hivemind".

## Common Gotchas

**Submodules:** HAF, reputation_tracker, and hafah are git submodules. Always clone with `--recurse-submodules`.

**Virtual Environment:** The Python package must be installed. Use `pip install .` in a virtual environment.

**PostgreSQL Access:** Indexer needs `hivemind` role, setup needs `haf_admin` role.

**Community Start Block:** In production, communities start at a specific block well after 5M. Use `--community-start-block` for testing with 5M block_log.

**Mock Data Required:** API tests need mock operations injected (see test setup above) because 5M blocks lack recent operations.

**Reputation Tracker Sync Order:** Must sync reputation_tracker to 4,999,979 BEFORE Hivemind completes massive sync, as Hivemind builds notification cache after massive sync.

**Nginx Rewriter Required:** The server requires nginx/openresty to rewrite JSON-RPC to REST calls. Without it, API calls fail.

**Ruff Formatting:** All Python code must be linted and formatted with `ruff` before committing.

**PostgREST Version:** Requires PostgREST 12.0.2 exactly.

## CI Pipeline

The `.gitlab-ci.yaml` defines the build/test pipeline. Key jobs:
- Build Docker images (base, instance, rewriter)
- Sync to 5M blocks with mock data
- Run API smoketests (bridge, condenser, negative)
- Benchmarking tests

Uses NFS cache at `/nfs/ci-cache` for sharing sync data across builders.

## CI sync decision

A full hivemind sync costs CI 14–18 minutes. `detect_changes` decides by path whether a pipeline needs one, and paths can't tell a change that alters synced data from one that doesn't. So whoever writes a commit (the implementing agent or a human) can declare it with a commit trailer:

```
Hivemind-Sync: required
Hivemind-Sync: not-required
```

**`required`** — the change alters what the indexer writes or how synced data is shaped:
- `hive/indexer/**`;
- `hive/utils/**` reached from the indexer;
- table, index and constraint DDL (`hive/db/sql_scripts/schema/*`, `register_indexes.sql`);
- `hive/db/sql_scripts/upgrade/*`;
- SQL the sync runs (`massive_sync.sql`, `update_*` / `process_*`, `hafapp_api.sql`, …);
- `scripts/install_app.sql`, `scripts/setup_postgres.sh`;
- anything else that changes the contents of `hivemind_app` tables.

**`not-required`** — read-side only:
- PostgREST and endpoint SQL (`hive/db/sql_scripts/postgrest/`, `endpoints/`);
- registering a script in the PostgREST load list;
- Python used only by the API server;
- tests, docs, `.aidev/`, CI.

**When unsure, `required`.** A wrong `not-required` lets the API tests run against data synced by older code.

How CI applies it (`scripts/ci/sync_decision.sh`, run in `detect_changes`'s `after_script`):
- any commit in the pipeline's range saying `required` forces a full sync, even for a docs-only change;
- a file changed only by commits saying `not-required` stops counting against the PostgREST-only mode (reload SQL on cached data), except files matching `^hive/indexer/|^hive/db/sql_scripts/(schema|upgrade)/|massive_sync\.sql$|^scripts/install_app\.sql$|^scripts/setup_postgres\.sh$`, which always need a sync;
- commits without the trailer, and merge commits, are classified by path as before;
- pipelines on `develop` and `master` ignore `not-required`, so a wrong skip shows up on the first pipeline after merge.
