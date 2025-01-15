# Hivemind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Developer-friendly microservice powering social networks on the Hive blockchain**
Hivemind is a "consensus interpretation" layer for the Hive blockchain, maintaining the state of social features such as
post feeds, follows, and communities. Written in Python, it synchronizes an SQL database with chain state, providing
developers with a more flexible/extensible alternative to the raw hived API.

## Table of Contents

1. [Environment](#environment)
   - [Dependencies](#dependencies)
1. [Installation](#installation)
   - [Prerequisites](#prerequisites)
   - [Installing Hivemind](#install-the-hivemind-itself)
   - [Installation of dockerized version](#dockerized-setup)
1. [Tests](#tests)
1. [Configuration](#configuration)
1. [Requirements](#requirements)
   - [Hardware](#hardware)
   - [Hived config](#hived-config)
   - [PostgreSQL performance](#postgresql-performance)
1. [JSON-RPC API](#json-rpc-api)
1. [Overview](#overview)
   - [Puropose](#purpose)
   - [Core indexer](#core-indexer)
   - [Cache layer](#cache-layer)
   - [API layer](#api-layer)
   - [Fork resolution](#fork-resolution)
1. [Documentation](#documentation)
<!-- The commented out section does not exist yet -->
<!-- 1. [Production Environment](#production-environment) -->

## Environment

- Python 3.8+ required
- Python dependencies: `pip >= 22.2.2` and `setuptools >= 63.1.0`
- Postgres 17 recommended

### Dependencies

- Ubuntu: `sudo apt-get install python3 python3-pip python3-venv`

## Installation

### Prerequisites

Hivemind is a [HAF](https://gitlab.syncad.com/hive/haf)-based application. To work properly it requires an existing
and working HAF database.

Clone the hivemind repository with its submodules:

```bash
git clone --recurse-submodules https://gitlab.syncad.com/hive/hivemind.git
cd hivemind
```

Update your global Python installation tools, by specifying:

```bash
python3 -m pip install --upgrade pip setuptools wheel
```

### Install the Hivemind itself

You can install additional dependencies for testing, development etc.
All the dependencies are listed in the `setup.cfg` file under the `[options.extras_require]` section.
You can include them by adding the extra flag to install command like:

```bash
pip install .'[tests]'
````

<details>
<summary>Install in virtual environment manually (RECOMMENDED)</summary>

```bash
cd hivemind                # Go to the hivemind repository
python3 -m venv venv/      # Create virtual environment in the ./venv/ directory
. venv/bin/activate        # Activate it
pip install .              # Install Hivemind
```

Now everytime you want to start the hivemind indexer or API server, you should activate the virtual environment with:

```bash
cd hivemind
. venv/bin/activate
```

To deactivate virtual environment run:

```bash
deactivate
```

</details>

<details>
<summary>Install in your operating system scope</summary>

Enter following command in terminal:

```bash
cd hivemind
pip install --no-cache-dir --verbose --user . 2>&1 | tee pip_install.log
```

</details>

### Dockerized setup

1. Firstly, we need a working HAF instance. Create some working directory (example workplace-haf on the same level as haf directory) and we can build it via docker:
```
../haf/scripts/ci-helpers/build_instance.sh local-haf-develop ../haf/ registry.gitlab.syncad.com/hive/haf/
```

2. For testing purposes we need a 5M block_log, so in order to avoid syncing in `workplace-haf` directory we create blockchain directory and copy there a block_log (split or monolit block_log). We can skip this step and go to 3rd step directly, but we need to remove `--replay` option in order to let hive download 5M blocks.
```
└── workplace-haf
    ├── blockchain
    │   └── block_log
```

3. Prepare HAF database - replay:
```
../haf/scripts/run_hived_img.sh registry.gitlab.syncad.com/hive/haf/instance:local-haf-develop --name=haf-instance --webserver-http-endpoint=8091 --webserver-ws-endpoint=8090  --data-dir=$(pwd) --docker-option="--shm-size=4294967296" --replay --stop-at-block=5000000
```

Replay will be finished when you see these logs:
```
2025-01-15T12:06:28.244946 livesync_data_dumper.cpp:85   livesync_data_dumper ] livesync dumper created
2025-01-15T12:06:28.244960 data_processor.cpp:68         operator()           ] Account operations data writer_1 data processor connected successfully ...
2025-01-15T12:06:28.244971 indexation_state.cpp:429      flush_all_data_to_re ] Flushing reversible blocks...
2025-01-15T12:06:28.244976 data_processor.cpp:66         operator()           ] Applied hardforks data writer data processor is connecting ...
2025-01-15T12:06:28.244991 indexation_state.cpp:445      flush_all_data_to_re ] Flushed all reversible blocks
2025-01-15T12:06:28.245001 data_processor.cpp:68         operator()           ] Applied hardforks data writer data processor connected successfully ...
2025-01-15T12:06:28.245016 indexation_state.cpp:379      update_state         ] PROFILE: Entered LIVE sync from start state: 606 s 5000000
2025-01-15T12:06:28.245047 chain_plugin.cpp:485          operator()           ] entering API mode
```

Everytime when you want to run tests or do anything with hivemind, you need to run above command and wait until above logs appear.

4. Update haf docker in order to allow connecting to postgres DB. You can use for that case `lazydocker` for example - in that case run lazydocker, choose proper docker container and then press shift+e in order to enter container.
Add to `/etc/postgresql/17/main/pg_hba.conf` these lines: (sudo may be needed)
```
host all all 0.0.0.0/0 trust
local all all peer
```
then restart postgresql: `sudo /etc/init.d/postgresql restart` (if for some reason docker container shutdown, just repeat step 3 and this one)

Now HAF database is ready to apply hivemind part. You can explore DB inside container with: `PGOPTIONS='-c search_path=hafd' psql -U haf_admin -d haf_block_log`

5. Build hivemind image (assuming we run this cmd inside `workplace-hivemind` directory which is on the same level as `hivemind` directory):
```
../hivemind/scripts/ci-helpers/build_instance.sh local-hivemind-develop ../hivemind registry.gitlab.syncad.com/hive/hivemind
```

6. Install hivemind *with mocks* (test data):
```
../hivemind/scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local-hivemind-develop install_app --database-admin-url="postgresql://haf_admin@172.17.0.2/haf_block_log" --with-reptracker --add-mocks="true"
```

you should see a lot of logs like: `INFO:hive.indexer.mocking.mock_block:OperationMock pushed successfully!` - it means mock data was applied.

7. Install reputation tracker:
```
../hivemind/reputation_tracker/scripts/process_blocks.sh --stop-at-block=4999979 --postgres-url="postgresql://haf_admin@172.17.0.2/haf_block_log"
```


8. Begin sync process (it will take a while).
Note - make sure that the mocks have been added correctly via: `SELECT num FROM hafd.blocks ORDER BY NUM DESC LIMIT 1;` - this query should return `5000024` - if you still have `5000000`, you need to repeat previous steps (uninstall hivemind app or remove db and recreate it).
Start sync process with:
```
../hivemind/scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local-hivemind-develop sync --database-url="postgresql://hivemind@172.17.0.2:5432/haf_block_log" --community-start-block 4998000 --test-max-block=5000024
```

9. Finish installing reputation tracker:
```
../hivemind/reputation_tracker/scripts/process_blocks.sh --stop-at-block=5000024 --postgres-url="postgresql://haf_admin@172.17.0.2/haf_block_log"
```

After this 9 steps your local hivemind instance is ready for testing purposes.
If you want to uninstall hivemind (you will need to repeat all hivemind install steps):
```
../hivemind/scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local-hivemind-develop uninstall_app --database-admin-url="postgresql://haf_admin@172.17.0.2/haf_block_log"
```

If you updated some sql files and want to reload sql queries etc:
1. Build again hivemind docker image
2. Run:
```
../hivemind/scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local-hivemind-develop install_app --upgrade-schema --database-admin-url="postgresql://haf_admin@172.17.0.2/haf_block_log"
```

## Tests

To run api tests:

1. Make sure that the current version of `hivemind` is installed,
2. Api tests require that `hivemind` is synced to a node replayed up to `5_000_024` blocks (including mocks).
3. Run `hivemind` in `server` mode
  (you may need to uncomment `export PGRST_DB_ROOT_SPEC="home"` from `scripts/start_postgrest.sh`. Otherwise, empty jsons could be returned , because postgrest doesn't support jsonrpc and there must be a proxy which handles this problem)
  We can launch postgrest server in two ways (from root directory of `hivemind` repo):
  -via docker:
  ```
  ./scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local-hivemind-develop server --database-url="postgresql://hivemind@172.17.0.2:5432/haf_block_log" --http-server-port=8080
  ```
  - directly launching script:
  `./scripts/start_postgrest.sh --host=172.17.0.2`
4. Run test:
While postgrest server is on, we can run all test cases from specific directory (again from root directory of `hivemind` repo):
```
./scripts/ci/start-api-smoketest.sh localhost 8080 follow_api_patterns result.xml 8
```
Which will launch all tests from `follow_api_patterns` directory.

To run only one, specific test case:
```
./scripts/ci/start-api-smoketest.sh localhost 8080 condenser_api_patterns/get_blog/limit_0.tavern.yaml result.xml 8
```

You can also check response from database with:
```
select * from hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "condenser_api.get_follow_count", "params": ["gtg"]}'::json);
```

or via curl:
```
curl localhost:8080 --header "Content-Type: application/json" --data '{"id": "cagdbc1", "method": "condenser_api.get_follow_count", "params": ["gtg"], "jsonrpc": "2.0"}'
```

## Configuration

| Environment        | CLI argument         | Default                                    |
|--------------------|----------------------|--------------------------------------------|
| `LOG_LEVEL`        | `--log-level`        | INFO                                       |
| `HTTP_SERVER_PORT` | `--http-server-port` | 8080                                       |
| `DATABASE_URL`     | `--database-url`     | postgresql://user:pass@localhost:5432/hive |
| `MAX_BATCH`        | `--max-batch`        | 35                                         |
| `MAX_WORKERS`      | `--max-workers`      | 6                                          |
| `MAX_RETRIES`      | `--max-retries`      | -1                                         |

Precedence: CLI over ENV over hive.conf. Check `hive --help` for details.

## Requirements

### Hardware

- Focus on Postgres performance
- 9GB of memory for `hive sync` process
- 750GB storage for hivemind's use of the database

### Hived config

Plugins

- Required: `sql_serializer`

### PostgreSQL Performance

For a system with 16G of memory, here's a good start:

```properties
effective_cache_size = 12GB # 50-75% of avail memory
maintenance_work_mem = 2GB
random_page_cost = 1.0      # assuming SSD storage
shared_buffers = 4GB        # 25% of memory
work_mem = 512MB
synchronous_commit = off
checkpoint_completion_target = 0.9
checkpoint_timeout = 30min
max_wal_size = 4GB
```

## JSON-RPC API

This is the core API set:

```bash
condenser_api.get_followers
condenser_api.get_following
condenser_api.get_follow_count

condenser_api.get_content
condenser_api.get_content_replies

condenser_api.get_state

condenser_api.get_trending_tags

condenser_api.get_discussions_by_trending
condenser_api.get_discussions_by_hot
condenser_api.get_discussions_by_promoted
condenser_api.get_discussions_by_created

condenser_api.get_discussions_by_blog
condenser_api.get_discussions_by_feed
condenser_api.get_discussions_by_comments
condenser_api.get_replies_by_last_update

condenser_api.get_blog
condenser_api.get_blog_entries
condenser_api.get_discussions_by_author_before_date
```

## Overview

### Purpose

Hivemind is a 2nd layer microservice that reads blocks of operations and virtual operations generated by the Hive
blockchain network (hived nodes), then organizes the data from these operations into a convenient form for querying by
Hive applications.
Hivemind's API is focused on providing social media-related information to Hive apps. This includes information about
posts, comments, votes, reputation, and Hive user profiles.

#### Hivemind tracks posts, relationships, social actions, custom operations, and derived states

- *discussions:* by blog, trending, hot, created, etc
- *communities:* mod roles/actions, members, feeds (in
  1.5; [spec](https://gitlab.syncad.com/hive/hivemind/-/blob/master/docs/communities.md))
- *accounts:* normalized profile data, reputation
- *feeds:* un/follows and un/reblogs

#### Hivemind does not track most blockchain operations

For anything to do with wallets, orders, escrow, keys, recovery, or account history, you should query hived.

#### Hivemind can be extended or leveraged to create

- reactions, bookmarks
- comment on reblogs
- indexing custom profile data
- reorganize old posts (categorize, filter, hide/show)
- voting/polls (democratic or burn/send to vote)
- modlists: (e.g. spammy, abuse, badtaste)
- crowdsourced metadata
- mentions indexing
- full-text search
- follow lists
- bot tracking
- mini-games
- community bots

### Core indexer

Ingests blocks sequentially, processing operations relevant to accounts, post creations/edits/deletes, and custom_json
ops for follows, reblogs, and communities. From these we build account and post lookup tables, follow/reblog state, and
communities/members data. Built exclusively from raw blocks, it becomes the ground truth for internal state. Hive does
not reimplement logic required for deriving payout values, reputation, and other statistics which are much more easily
attained from hived itself in the cache layer.

For efficiency reasons, when first started, hive sync will begin in an "initial sync" mode where it processes in chunks
of 1000 blocks at a time until it gets near the current head block, then it will switch to LIVE SYNC mode, where it
begins processing blocks one at a time, as they are produced by hive nodes. Before it switches to LIVE SYNC mode, hive
sync will create the database indexes necessary for hive server to efficiently process API queries.

### Cache layer

Synchronizes the latest state of posts and users, allowing us to serve discussions and lists of posts with all expected
information (title, preview, image, payout, votes, etc) without needing `hived`. This layer is first built once the
initial core indexing is complete. Incoming blocks trigger cache updates (including recalculation of trending score) for
any posts referenced in `comment` or `vote` operations. There is a sweep to paid out posts to ensure they are updated in
full with their final state.

### API layer

Performs queries against the core and cache tables, merging them into a response in such a way that the frontend will
not need to perform any additional calls to `hived` itself. The initial API simply mimics hived's `condenser_api` for
backwards compatibility, but will be extended to leverage new opportunities and simplify application development.

### Fork Resolution

**Latency vs. consistency vs. complexity**
The easiest way to avoid forks is to only index up to the last irreversible block, but the delay is too much where users
expect quick feedback, e.g. votes and live discussions. We can apply the following approach:

1. Follow the chain as closely to `head_block` as possible
2. Indexer trails a few blocks behind, by no more than 6s - 9s
3. If missed blocks detected, back off from `head_block`
4. Database constraints on block linking to detect failure asap
5. If a fork is encountered between `hive_head` and `steem_head`, trivial recovery
6. Otherwise, pop blocks until in sync. Inconsistent state possible but rare for `TRAIL_BLOCKS > 1`.
7. A separate service with a greater follow distance creates periodic snapshots

## Documentation

```bash
make docs && open docs/hive/index.html
```
