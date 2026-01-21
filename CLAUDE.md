# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Hivemind** is a HAF (Hive Application Framework)-based microservice that provides social media features for the Hive
blockchain. It consists of two main components:

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
pip install .'[dev]'            # With dev tools (black, pyYAML)
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

**ALWAYS run black before committing Python code:**

```bash
cd <repo_root>
pip install .'[dev]'  # If not already installed
black hive/          # Format all Python in hive/
black <file.py>      # Format specific file
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
│   ├── schema.py          # Table definitions (Python SQLAlchemy)
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

-   Hivemind uses the `hivemind_app` context/schema
-   Only processes irreversible blocks (no micro-fork handling needed)
-   Depends on `reputation_tracker` application (default schema: `reptracker_app`)

**Database Schemas:**

-   `hivemind_app`: Application tables with social data
-   `hivemind_endpoints`: Server functions called by PostgREST
-   `hivemind_postgrest_utilities`: Utilities for endpoints

**Database Roles:**

-   `hivemind`: Used for running sync and server

**Server Architecture:**

-   PostgREST exposes PostgreSQL functions as REST endpoints
-   Nginx/openresty rewrites JSON-RPC calls to `/rpc/home` endpoint
-   All API logic is in PL/pgSQL functions in `hive/db/sql_scripts/postgrest/`

**Entry Points (setup.cfg):**

-   `hive`: Main CLI (routes to sync, build_schema, upgrade_schema, status)
-   `mocker`: Inject mock data into HAF for testing

**Dependencies (Python):**

-   SQLAlchemy 1.4.49 for HAF database access
-   aiopg, aiohttp for async operations
-   configargparse for configuration
-   psycopg2-binary for PostgreSQL

**Testing Framework:**

-   Tavern (pytest plugin) for API tests (YAML-based)
-   Tests are in `tests/api_tests/hivemind/tavern/`
-   Run via tox with `-e tavern`

## Common Gotchas

**Submodules:** HAF, reputation_tracker, and hafah are git submodules. Always clone with `--recurse-submodules`.

**Virtual Environment:** The Python package must be installed. Use `pip install .` in a virtual environment.

**PostgreSQL Access:** Indexer needs `hivemind` role, setup needs `haf_admin` role.

**Community Start Block:** In production, communities start at a specific block well after 5M. Use
`--community-start-block` for testing with 5M block_log.

**Mock Data Required:** API tests need mock operations injected (see test setup above) because 5M blocks lack recent
operations.

**Reputation Tracker Sync Order:** Must sync reputation_tracker to 4,999,979 BEFORE Hivemind completes massive sync, as
Hivemind builds notification cache after massive sync.

**Nginx Rewriter Required:** The server requires nginx/openresty to rewrite JSON-RPC to REST calls. Without it, API
calls fail.

**Black Formatting:** All Python code must be formatted with `black` before committing.

**PostgREST Version:** Requires PostgREST 12.0.2 exactly.

## CI Pipeline

The `.gitlab-ci.yaml` defines the build/test pipeline. Key jobs:

-   Build Docker images (base, instance, rewriter)
-   Sync to 5M blocks with mock data
-   Run API smoketests (bridge, condenser, negative)
-   Benchmarking tests

Uses NFS cache at `/nfs/ci-cache` for sharing sync data across builders.
