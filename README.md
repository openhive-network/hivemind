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
1. [Updating from an existing hivemind database](#updating-from-an-existing-hivemind-database)
1. [Running](#running)
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
- Postgres 12+ recommended

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

#### Building

To build image holding Hivemind instance, please use [build_instance.sh](scripts/ci-helpers/build_instance.sh). This script requires several parameters:

- a tag identifier to be set on the built image
- directory where Hivemind source code is located
- docker registry url to produce fully qualified image name and allow to correctly resolve its dependencies

```bash
# Assuming you are in workdir directory, to perform out of source build
../hivemind/scripts/ci-helpers/build_instance.sh local ../hivemind registry.gitlab.syncad.com/hive/hivemind
```

#### Running HAF instance container

A Hivemind instance requires a HAF instance to process incoming blockchain data collected and to store its own data in fork-resistant manner (allows hivemind data to be reverted in case of a fork).
The easiest way to setup a HAF instance is to use a dockerized instance.

To start a HAF instance, we need to prepare a data directory containing:

- a blockchain subdirectory (where can be put the block_log file used by hived)
- optionally, but very useful, a copy of haf/doc/haf_postgresql_conf.d directory, which allows simple customization of Postgres database setup by modification of `custom_postgres.conf` and `custom_pg_hba.conf` files stored inside.

Please take care to set correct file permissions in order to provide write access to the data directory for processes running inside the HAF container.

```bash
cd /storage1/haf-data-dir/
../hivemind/haf/scripts/run_hived_img.sh registry.gitlab.syncad.com/hive/haf/instance:<tag> --name=haf-mainnet-instance  --data-dir="$(pwd)" <hived-options>
```

For example, for testing purposes (assuming block_log file has been put into data-dir), you can spawn a 5M block replay to prepare a HAF database for further quick testing:

```bash
../hivemind/haf/scripts/run_hived_img.sh registry.gitlab.syncad.com/hive/haf/instance:instance-v1.27.3.0 --name=haf-mainnet-instance  --data-dir="$(pwd)" --replay --stop-at-block=5000000
```

By examining hived.log file or using docker logs haf-mainnet-instance, you can examine state of the started instance. Once replay will be finished, you can continue and start the Hivemind sync process.

Example output of hived process stopped on 5,000,000th block:

```bash
2022-12-19T18:28:05.574637 chain_plugin.cpp:701          replay_blockchain    ] Stopped blockchain replaying on user request. Last applied block numbe
r: 5000000.
2022-12-19T18:28:05.574658 chain_plugin.cpp:966          plugin_startup       ] P2P enabling after replaying...
2022-12-19T18:28:05.574670 chain_plugin.cpp:721          work                 ] Started on blockchain with 5000000 blocks, LIB: 4999980
2022-12-19T18:28:05.574687 chain_plugin.cpp:727          work                 ] Started on blockchain with 5000000 blocks
2022-12-19T18:28:05.574736 chain_plugin.cpp:993          plugin_startup       ] Chain plugin initialization finished...
2022-12-19T18:28:05.574753 sql_serializer.cpp:712        plugin_startup       ] sql::plugin_startup()
2022-12-19T18:28:05.574772 p2p_plugin.cpp:466            plugin_startup       ] P2P plugin startup...
2022-12-19T18:28:05.574764 chain_plugin.cpp:339          operator()           ] Write processing thread started.
2022-12-19T18:28:05.574782 p2p_plugin.cpp:470            plugin_startup       ] P2P plugin is not enabled...
2022-12-19T18:28:05.574840 witness_plugin.cpp:648        plugin_startup       ] witness plugin:  plugin_startup() begin
2022-12-19T18:28:05.574866 witness_plugin.cpp:655        plugin_startup       ] Witness plugin is not enabled, beause P2P plugin is disabled...
2022-12-19T18:28:05.574885 wallet_bridge_api_plugin.cpp:20 plugin_startup       ] Wallet bridge api plugin initialization...
2022-12-19T18:28:05.574905 wallet_bridge_api.cpp:169     api_startup          ] Wallet bridge api initialized. Missing plugins: database_api block_api
 account_history_api market_history_api network_broadcast_api rc_api_plugin
2022-12-19T18:28:05.575624 webserver_plugin.cpp:240      operator()           ] start processing ws thread
Entering application main loop...
2022-12-19T18:28:05.575687 webserver_plugin.cpp:261      operator()           ] start listening for http requests on 0.0.0.0:8090
2022-12-19T18:28:05.575716 webserver_plugin.cpp:263      operator()           ] start listening for ws requests on 0.0.0.0:8090
2022-12-19T18:28:35.575535 chain_plugin.cpp:380          operator()           ] No P2P data (block/transaction) received in last 30 seconds... peer_count=0
```

#### Running Hivemind instance container

The built Hivemind instance requires a preconfigured HAF database to store its data. You  can perform them with `install_app` command before starting the sync.

The commands below assume that the running HAF container has IP: 172.17.0.2

```bash
# Set-up Database
../hivemind/scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local install_app \
   --database-admin-url="postgresql://haf_admin@172.17.0.2/haf_block_log" # haf_admin access URL

# Run the sync
../hivemind/scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local sync \
   --database-url="postgresql://hivemind@172.17.0.2:5432/haf_block_log"
```

## Updating from an existing hivemind database

```bash
../hivemind/scripts/run_instance.sh registry.gitlab.syncad.com/hive/hivemind/instance:local install_app --upgrade-schema \
   --database-admin-url="postgresql://haf_admin@172.17.0.2/haf_block_log" # haf_admin access URL
```

(where *user-name* is your database login name)

## Running

Export the URL to your HAF database:

```bash
export DATABASE_URL=postgresql://hivemind_app:pass@localhost:5432/haf_block_log
```

### Start the hivemind indexer (aka synchronization process)

```bash
hive sync
```

```bash
$ hive status
{'db_head_block': 19930833, 'db_head_time': '2018-02-16 21:37:36', 'db_head_age': 10}
```

### Start the hivemind API server

```bash
hive server
```

```bash
$ curl --data '{"jsonrpc":"2.0","id":0,"method":"hive.db_head_state","params":{}}' http://localhost:8080
{"jsonrpc": "2.0", "result": {"db_head_block": 19930795, "db_head_time": "2018-02-16 21:35:42", "db_head_age": 10}, "id": 0}
```

## Tests

To run api tests:

1. Make sure that the current version of `hivemind` is installed,
2. Api tests require that `hivemind` is synced to a node replayed up to `5_000_024` blocks (including mocks).\
   This means, you should have your HAF database replayed up to `5_000_000` mainnet blocks and run the mocking script with:

    ```bash
    cd hivemind/scripts/ci/
    ./scripts/ci/add-mocks-to-db.sh --postgres-url="postgresql://haf_admin@172.17.0.2/haf_block_log" # haf_admin access URL, assuming HAF is running on 172.17.0.2
    ```

3. Run `hivemind` in `server` mode
4. Set env variables:

    ```bash
    export HIVEMIND_PORT=8080
    export HIVEMIND_ADDRESS=127.0.0.1
    ```

5. Run tests using tox:

    ```bash
    tox -e tavern -- -n auto --durations=0
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
information (title, image, payout, votes, etc) without needing `hived`. This layer is first built once the
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
