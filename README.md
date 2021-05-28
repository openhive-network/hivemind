# Hivemind

#### Developer-friendly microservice powering social networks on the Hive blockchain.

Hivemind is a "consensus interpretation" layer for the Hive blockchain, maintaining the state of social features such as post feeds, follows, and communities. Written in Python, it synchronizes an SQL database with chain state, providing developers with a more flexible/extensible alternative to the raw hived API.

## Development Environment

 - Python 3.6+ required
 - Postgres 10+ recommended

### Dependencies:

 - OSX: `$ brew install python3 postgresql`
 - Ubuntu: `$ sudo apt-get install python3 python3-pip`

### Installation:

Before creating the hive database, Hivemind requires the postgresql 'intarray' extension. The postgresql user who has CREATE privilege can load the module with the command `CREATE EXTENSION IF NOT EXISTS intarray;`.

```bash
$ createdb hive
$ export DATABASE_URL=postgresql://user:pass@localhost:5432/hive
```

```bash
$ git clone --recurse-submodules https://gitlab.syncad.com/hive/hivemind.git
$ cd hivemind
$ python3 -m pip install --no-cache-dir --verbose --user -e .[dev] 2>&1 | tee pip_install.log
```

### Updating from an existing hivemind database:

```bash
$ cd hivemind
$ python3 -m pip install --no-cache-dir --verbose --user -e .[dev] 2>&1 | tee pip_install.log
$ ./hive/db/sql_scripts/db_upgrade.sh
```

### Start the indexer:

```bash
$ hive sync
```

```bash
$ hive status
{'db_head_block': 19930833, 'db_head_time': '2018-02-16 21:37:36', 'db_head_age': 10}
```

### Start the server:

```bash
$ hive server
```

```bash
$ curl --data '{"jsonrpc":"2.0","id":0,"method":"hive.db_head_state","params":{}}' http://localhost:8080
{"jsonrpc": "2.0", "result": {"db_head_block": 19930795, "db_head_time": "2018-02-16 21:35:42", "db_head_age": 10}, "id": 0}
```

### Run tests:

To run unit tests:

```bash
$ make test
```

To run api tests:
1. Make sure that current version of `hivemind` is installed,
2. Api tests require that `hivemind` is synced to a node replayed up to 5 000 000 blocks,
3. Run `hivemind` in `server` mode
4. Set env variables:
```bash
$ export HIVEMIND_PORT=8080
$ export HIVEMIND_ADDRESS=127.0.0.1
```
5. Run tests using tox:
```bash
$ tox -e tavern -- --workers auto --tests-per-worker auto --durations=0
```

## Production Environment

Hivemind is deployed as a Docker container.

Here is an example command that will initialize the database schema and start the syncing process:

```
docker run -d --name hivemind --env DATABASE_URL=postgresql://user:pass@hostname:5432/databasename --env STEEMD_URL='{"default":"https://yourhivenode"}' --env SYNC_SERVICE=1 -p 8080:8080 hive/hivemind:latest
```

Be sure to set `DATABASE_URL` to point to your postgres database and set `STEEMD_URL` to point to your hived node to sync from.

Once the database is synced, Hivemind will be available for serving requests.

To watch the logs on your console:

```
docker logs -f hivemind
```


## Configuration

| Environment              | CLI argument         | Default |
| ------------------------ | -------------------- | ------- |
| `LOG_LEVEL`              | `--log-level`        | INFO    |
| `HTTP_SERVER_PORT`       | `--http-server-port` | 8080    |
| `DATABASE_URL`           | `--database-url`     | postgresql://user:pass@localhost:5432/hive |
| `STEEMD_URL`             | `--steemd-url`       | '{"default":"https://yourhivenode"}' |
| `MAX_BATCH`              | `--max-batch`        | 50      |
| `MAX_WORKERS`            | `--max-workers`      | 4       |
| `TRAIL_BLOCKS`           | `--trail-blocks`     | 2       |

Precedence: CLI over ENV over hive.conf. Check `hive --help` for details.


## Requirements



### Hardware

 - Focus on Postgres performance
 - 2.5GB of memory for `hive sync` process
 - 500GB storage for database


### Hive config

Plugins

 - Required: `database_api condenser_api block_api account_history_api account_history_rocksdb`
 - Not required: `follow*`, `tags*`, `market_history`, `account_history` (obsolete, do not use), `witness`


### Postgres Performance

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

The minimum viable API is to remove the requirement for the `follow` and `tags` plugins (now rolled into [`condenser_api`](https://gitlab.syncad.com/hive/hive/-/tree/master/libraries/plugins/apis/condenser_api/condenser_api.cpp)) from the backend node while still being able to power condenser's non-wallet features. Thus, this is the core API set:

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

Hivemind is a 2nd layer microservice that reads blocks of operations and virtual operations generated by the Hive blockchain network (hived nodes), then organizes the data from these operations into a convenient form for querying by Hive applications.
Hivemind's API is focused on providing social media-related information to Hive apps. This includes information about posts, comments, votes, reputation, and Hive user profiles.

##### Hivemind tracks posts, relationships, social actions, custom operations, and derived states.

 - *discussions:* by blog, trending, hot, created, etc
 - *communities:* mod roles/actions, members, feeds (in 1.5; [spec](https://gitlab.syncad.com/hive/hivemind/-/blob/master/docs/communities.md))
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

Ingests blocks sequentially, processing operations relevant to accounts, post creations/edits/deletes, and custom_json ops for follows, reblogs, and communities. From these we build account and post lookup tables, follow/reblog state, and communities/members data. Built exclusively from raw blocks, it becomes the ground truth for internal state. Hive does not reimplement logic required for deriving payout values, reputation, and other statistics which are much more easily attained from hived itself in the cache layer.

For efficiency reasons, when first started, hive sync will begin in an "initial sync" mode where it processes in chunks of 1000 blocks at a time until it gets near the current head block, then it will switch to LIVE SYNC mode, where it begins processing blocks one at a time, as they are produced by hive nodes. Before it switches to LIVE SYNC mode, hive sync will create the database indexes necessary for hive server to efficiently process API queries.

#### Cache layer

Synchronizes the latest state of posts and users, allowing us to serve discussions and lists of posts with all expected information (title, preview, image, payout, votes, etc) without needing `hived`. This layer is first built once the initial core indexing is complete. Incoming blocks trigger cache updates (including recalculation of trending score) for any posts referenced in `comment` or `vote` operations. There is a sweep to paid out posts to ensure they are updated in full with their final state.

#### API layer

Performs queries against the core and cache tables, merging them into a response in such a way that the frontend will not need to perform any additional calls to `hived` itself. The initial API simply mimics hived's `condenser_api` for backwards compatibility, but will be extended to leverage new opportunities and simplify application development.


#### Fork Resolution

**Latency vs. consistency vs. complexity**

The easiest way to avoid forks is to only index up to the last irreversible block, but the delay is too much where users expect quick feedback, e.g. votes and live discussions. We can apply the following approach:

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

## License

MIT
