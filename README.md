# Hivemind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

#### Developer-friendly microservice powering social networks on the Hive blockchain.

Hivemind is a "consensus interpretation" layer for the Hive blockchain, maintaining the state of social features such as
post feeds, follows, and communities. Written in Python, it synchronizes an SQL database with chain state, providing
developers with a more flexible/extensible alternative to the raw hived API.

## Table of Contents

1. [Environment](#environment)
2. [Installation](#installation)
3. [Updating from an existing hivemind database](#updating-from-an-existing-hivemind-database)
4. [Running](#running)
5. [Tests](#tests)
6. [Production Environment](#production-environment)
7. [Configuration](#configuration)
8. [Requirements](#requirements)
9. [JSON-RPC API](#json-rpc-api)
10. [Overview](#overview)
11. [Documentation](#documentation)

## Environment

- Python 3.8+ required
- Python dependencies: `pip >= 22.2.2` and `setuptools >= 63.1.0`
- Postgres 12+ recommended

#### Dependencies:

- Ubuntu: `$ sudo apt-get install python3 python3-pip python3-venv`

## Installation:

#### Prerequisites:

Hivemind is a [HAF](https://gitlab.syncad.com/hive/haf)-based application. To work properly it requires an existing
and working HAF database.

Hivemind also requires the postgresql `intarray` extension to be installed. The postgresql user who has `CREATE`
privilege can load the module with following command:

```postgresql
CREATE EXTENSION IF NOT EXISTS intarray;
```

Clone the hivemind repository with its submodules:

```bash
$ git clone --recurse-submodules https://gitlab.syncad.com/hive/hivemind.git
$ cd hivemind
```

Update your global Python installation tools, by specifying:

```bash
$ python3 -m pip install --upgrade pip setuptools wheel
```

#### Install the Hivemind itself:

You can install additional dependencies for testing, development etc.
All the dependencies are listed in the `setup.cfg` file under the `[options.extras_require]` section.
You can include them by adding the extra flag to install command like:

```bash
$ pip install .'[tests]'
````

<details>
<summary>Install in virtual environment manually (RECOMMENDED)</summary>

```bash
$ cd hivemind                # Go to the hivemind repository
$ python3 -m venv venv/      # Create virtual environment in the ./venv/ directory
$ . venv/bin/activate        # Activate it
$ pip install .              # Install Hivemind
```

Now everytime you want to start the hivemind indexer or API server, you should activate the virtual environment with:

```bash
$ cd hivemind
$ . venv/bin/activate
```

To deactivate virtual environment run:

```bash
$ deactivate
```

</details>

<details>
<summary>Install in your operating system scope</summary>

Enter following command in terminal:

```bash
$ cd hivemind
$ pip install --no-cache-dir --verbose --user . 2>&1 | tee pip_install.log
```

</details>

## Updating from an existing hivemind database

```bash
$ cd hivemind/hive/db/sql_scripts
$ ./db_upgrade.sh <user-name> hive
```

(where <user-name> is your database login name)

## Running

Indicate access to your HAF database:

```bash
$ export DATABASE_URL=postgresql://hivemind_app:pass@localhost:5432/hive
```

#### Start the indexer (aka synchronization process):

```bash
$ hive sync
```

```bash
$ hive status
{'db_head_block': 19930833, 'db_head_time': '2018-02-16 21:37:36', 'db_head_age': 10}
```

#### Start the API server:

```bash
$ hive server
```

```bash
$ curl --data '{"jsonrpc":"2.0","id":0,"method":"hive.db_head_state","params":{}}' http://localhost:8080
{"jsonrpc": "2.0", "result": {"db_head_block": 19930795, "db_head_time": "2018-02-16 21:35:42", "db_head_age": 10}, "id": 0}
```

## Tests:

To run api tests:

1. Make sure that current version of `hivemind` is installed,
2. Api tests require that `hivemind` is synced to a node replayed up to `5_000_024` blocks (including mocks).\
   This means, you should have HAF database replayed up to `5_000_000` mainnet blocks and run the mocking script with:

    ```bash
    $ cd hivemind/scripts/ci/
    $ ./scripts/ci/add-mocks-to-db.sh
    ```

3. Run `hivemind` in `server` mode
4. Set env variables:

    ```bash
    $ export HIVEMIND_PORT=8080
    $ export HIVEMIND_ADDRESS=127.0.0.1
    ```

5. Run tests using tox:

    ```bash
    $ tox -e tavern -- -n auto --durations=0
    ```

## Production Environment

Deploying Hivemind as a Docker container will be available when Hivemind HAf version will be released.

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

#### Hardware

- Focus on Postgres performance
- 9GB of memory for `hive sync` process
- 750GB storage for database

#### Hive config

Plugins

- Required: `database_api`,`condenser_api`,`block_api`,`account_history_api`

#### Postgres Performance

For a system with 16G of memory, here's a good start:

```
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

```
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

#### Purpose

Hivemind is a 2nd layer microservice that reads blocks of operations and virtual operations generated by the Hive
blockchain network (hived nodes), then organizes the data from these operations into a convenient form for querying by
Hive applications.
Hivemind's API is focused on providing social media-related information to Hive apps. This includes information about
posts, comments, votes, reputation, and Hive user profiles.

##### Hivemind tracks posts, relationships, social actions, custom operations, and derived states.

- *discussions:* by blog, trending, hot, created, etc
- *communities:* mod roles/actions, members, feeds (in
  1.5; [spec](https://gitlab.syncad.com/hive/hivemind/-/blob/master/docs/communities.md))
- *accounts:* normalized profile data, reputation
- *feeds:* un/follows and un/reblogs

##### Hivemind does not track most blockchain operations.

For anything to do with wallets, orders, escrow, keys, recovery, or account history, you should query hived.

##### Hivemind can be extended or leveraged to create:

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

#### Core indexer

Ingests blocks sequentially, processing operations relevant to accounts, post creations/edits/deletes, and custom_json
ops for follows, reblogs, and communities. From these we build account and post lookup tables, follow/reblog state, and
communities/members data. Built exclusively from raw blocks, it becomes the ground truth for internal state. Hive does
not reimplement logic required for deriving payout values, reputation, and other statistics which are much more easily
attained from hived itself in the cache layer.

For efficiency reasons, when first started, hive sync will begin in an "initial sync" mode where it processes in chunks
of 1000 blocks at a time until it gets near the current head block, then it will switch to LIVE SYNC mode, where it
begins processing blocks one at a time, as they are produced by hive nodes. Before it switches to LIVE SYNC mode, hive
sync will create the database indexes necessary for hive server to efficiently process API queries.

#### Cache layer

Synchronizes the latest state of posts and users, allowing us to serve discussions and lists of posts with all expected
information (title, preview, image, payout, votes, etc) without needing `hived`. This layer is first built once the
initial core indexing is complete. Incoming blocks trigger cache updates (including recalculation of trending score) for
any posts referenced in `comment` or `vote` operations. There is a sweep to paid out posts to ensure they are updated in
full with their final state.

#### API layer

Performs queries against the core and cache tables, merging them into a response in such a way that the frontend will
not need to perform any additional calls to `hived` itself. The initial API simply mimics hived's `condenser_api` for
backwards compatibility, but will be extended to leverage new opportunities and simplify application development.

#### Fork Resolution

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
$ make docs && open docs/hive/index.html
```
