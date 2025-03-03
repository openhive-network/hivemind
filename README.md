# Hivemind

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Developer-friendly microservice powering social networks on the Hive blockchain**

1. [Overview](#overview)
2. [Software Architecture](#software-architecture)
2. [Deployment](#deployment)
    - [Docker images repository]()
    - [Build images](#build-docker-images)
    - [Api Node](#deployment-using-the-haf-api-node)
    - [Starting containers manually](#deployment-without-haf-api-node)
    - [Setup on host](#development-on-local-host)
3. [API tests](#api-tests)

# Overview

Hivemind is a microservice that simplifies data access and enables the
development of rich social media applications on top of the Hive blockchain. It
maintains the state of social features such as post feeds, follows, and
communities, providing a consensus interpretation layer for Hive applications.

### Hivemind tracks posts, relationships, social actions, custom operations, and derived states

- *discussions:* by blog, trending, hot, created, etc
- *communities:* mod roles/actions, members, feeds (in
  1.5; [spec](https://gitlab.syncad.com/hive/hivemind/-/blob/master/docs/communities.md))
- *accounts:* normalized profile data, reputation
- *feeds:* un/follows and un/reblogs: [spec](https://gitlab.syncad.com/hive/hivemind/-/blob/master/docs/follows.md)

### Hivemind does not track most blockchain operations

For anything to do with wallets, orders, escrow, keys, recovery, or account history, you should query hived.

### Hivemind is a HAF application
Hivemind is based on the [**Hive Application Framework (HAF)**](https://gitlab.syncad.com/hive/haf/), which serves as a
"consensus interpretation" layer. HAF ensures data consistency and integrity
during blockchain synchronization by serializing the Hive blockchain into a
PostgreSQL database. Hivemind processes only irreversible blocks of the Hive
blockchain stored in the HAF database. This means that in the case of a micro
fork, when consensus is not reached, new data is not synced into its tables
until the fork is resolved and the new block data becomes irreversible.

Hivemind is divided into two parts:

1. **Indexer**: A **Hive Application Framework (HAF)**-based application written
   in **Python** that calls PostgreSQL-specific SQL to extract Hive social data
   from HAF tables and collect it into the application tables in a form that
   allows very performant access by frontend applications.

   For efficiency, hivemind sync operates in three stages:

   1. **MASSIVE_WITHOUT_INDEXES** – Used at the start when a very large number  
      of blocks must be processed before reaching the head block. Blocks are  
      processed in **1000-block batches** without indexes, ensuring maximum  
      insert speed, as maintaining indexes would slow processing.

   2. **MASSIVE_WITH_INDEXES** – Continues batch processing in **1000-block  
      batches**, but with indexes enabled. This ensures faster lookups but  
      slows inserts. This stage is used when index maintenance overhead is  
      justified.

   3. **LIVE** – Once near the head block, sync switches to **LIVE mode**,  
      processing blocks one at a time as they are produced by Hive nodes.

    Before entering **LIVE mode**, **Hivemind sync** creates the necessary  
    database indexes to optimize API query performance.

2. **Server**: Implemented in a **PostgreSQL-specific flavor of SQL**, it is
   called by [**PostgREST**](https://docs.postgrest.org/) to expose a JSON-RPC API, providing a flexible
   interface for clients to query social media-related data. PostgREST acts as
   a bridge, converting database functions into RESTful endpoints. The Hivemind API currently uses JSON-RPC,
   and **Nginx** is required to function as a reverse proxy, rewriting and redirecting all JSON-RPC 
   requests to the PostgREST endpoint.
   The server queries tables filled by the indexer to provide application
   data. Some API calls require Hive accounts reputation data. The server code
   relies on another HAF application, [**reputation-tracker**](https://gitlab.syncad.com/hive/reputation_tracker/), which must run
   alongside the Hivemind indexer to provide this functionality.

## Software architecture

Hivemind is undergoing a transformation from a traditional Python application
to a HAF-based system written entirely in PL/pgSQL. Currently, the server
component is fully defined in SQL, while the indexer remains in Python.

This transition involves major refactoring, which may leave behind some unusual
or unused code. Understanding these remnants often requires knowledge of the
project’s history.  

### Languages and libraries
- **Python 3.10** is used for the indexer. [SqlAlchemy 1.4.49](https://docs.sqlalchemy.org/en/14/) is used to access the HAF database from python.
The pip is used as python package manager, the packages with versions are defined in [setup.cfg](./setup.cfg)

- **PLpgSQL** is used for database tables and functions definitions
- **Bash** scripts used for setup and CI tools
- **YAML** for CI pipeline definition

### Sources organization

This table presents the Hivemind source code, showing only key parts.
It includes the HAF submodule, database definitions, indexer,
deployment scripts, and mock data. Non-essential dirs are omitted.

| **Directory Structure**                                                                    | **Description**                                                             |
|--------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------|
| **docker/**                                                                                | Docker entry points for containers                                          |
| **haf/**                                                                                   | HAF project - Git submodule                                                 |
| **hive/**                                                                                  | Hivemind code                                                               |
| &nbsp;&nbsp;&nbsp;&nbsp;├── *conf.py*                                                      | Definition of sync command-line parameters                                  |
| &nbsp;&nbsp;&nbsp;&nbsp;├── **db/**                                                        | Contains database element definitions                                       |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├── **schema.py**                          | Hivemind tables definitions                                                 |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├── **sql_scripts/**                       | Code written in pure PostgreSQL SQL                                         |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├── **postgrest/** | SQL definitions only for the server                                         |
| &nbsp;&nbsp;&nbsp;&nbsp;├── **indexer/**                                                   | Indexer implementation in Python                                            |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;├── *sync.py*                              | Synchronization loop implementation                                         |
| **mock_data/**                                                                             | Scripts that inject blocks and operations into a 5M HAF database for testing |
| **reputation_tracker/**                                                                    | Reputation tracker project - Git submodule                                  |
| **scripts/**                                                                               | Tools written as shell scripts                                              |
| &nbsp;&nbsp;&nbsp;&nbsp;├── **ci/**                                                        | Scripts used by the Continuous Integration process                          |
| &nbsp;&nbsp;&nbsp;&nbsp;├── *start-api-smoketest.sh*                                       | Starts API smoke testing                                                    |
| &nbsp;&nbsp;&nbsp;&nbsp;├── *install_app.sh*                                               | Installs Hivemind on the HAF database                                       |
| &nbsp;&nbsp;&nbsp;&nbsp;├── *uninstall_app.sh*                                             | Uninstalls Hivemind from the HAF database                                   |
| &nbsp;&nbsp;&nbsp;&nbsp;├── *setup_postgres.sh*                                            | Sets up Hivemind roles on the HAF database                                  |
| &nbsp;&nbsp;&nbsp;&nbsp;├── *start_postgrest.sh*                                           | Starts the PostgREST server                                                 |
| **tests/**                                                                                 | Tests                                                                       |


### Database

Hivemind is a HAF application, so it uses PostgreSQL. All details about  
PostgreSQL setup are encapsulated in HAF projects and their deployment  
procedures.

#### Roles
- **hivemind** - Used for running the HAF application synchronization process.

#### Schemas
- **hivemind_app** - Contains Hivemind tables for synchronized data.
- **hivemind_endpoints** - Contains functions used by the server.
- **hivemind_postgrest_utilities** - Contains utilities for server endpoints.

#### HAF Contexts

**Hivemind indexer** uses the HAF context `hivemind_app` with the schema  
`hivemind_app`. The context processes only irreversible blocks.

**Server** uses the `reputation_tracker` application, which is expected to be  
placed in the `reptracker_app` schema by default. However, it is possible to  
instruct Hivemind to seek the reputation tracker in a different schema using  
the `--reptracker-schema-name` option during setup.


## Deployment
For deployment purposes, Hivemind provides prebuilt Docker images available in the repository [gitlab.syncad.com/hive/hivemind](https://gitlab.syncad.com/hive/hivemind/container_registry/616).
These images include only the Hivemind components (indexer and server) and do not contain **HAF** or **reputation_tracker**,
they container needs to by started separately alongside with hivemind. Docker repositories for HAF: [gitlab.syncad.com/hive/haf](https://gitlab.syncad.com/hive/haf/container_registry/615)
and for reputation_tracker: [gitlab.syncad.com/hive/reputation_tracker](https://gitlab.syncad.com/hive/reputation_tracker/container_registry/629)

It is crucial to understand the dependencies between HAF, reputation_tracker, and the Hivemind components (indexer and server).
The installation must follow this specific order: **'HAF -> reputation_tracker -> hivemind indexer'**

Once all components are installed, they can be started. The internal implementation of HAF applications ensures that syncing begins only after
HAF reaches the head block and required SQL indexers are ready.

After **reputation_tracker** and **hivemind indexer** reach the head block and start live block syncing, the Hivemind server can then be started.

### Build docker images
You can use released containers from docker registry or You can build them from sources. Hivemind sources
contains all dependant elements -HAF and reputation_tracker as submodule.
```bash
git clone --recurse-submodules https://gitlab.syncad.com/hive/hivemind.git
cd hivemind
```
All the examples below starts in hivemind sources root folder.
1. Build **HAF**
   Build docker image, in the example below it will be named 'instance:local'
   ```bash
   cd haf
   ./scripts/ci-helpers/build_instance.sh local  $(pwd) registry.gitlab.syncad.com/hive/haf
   ```
2. Build **Reputation tracker** image
   Build docker image, in the example below it will be named 'local'
      ```bash
      cd reputation_tracker
      docker build -t registry.gitlab.syncad.com/hive/reputation_tracker:local .
      ```
4. **Hivemind**
    - Build **hivemind** docker image, in the example below it will be named 'local'
      ```bash
      ./scripts/ci-helpers/build_instance.sh local  $(pwd) registry.gitlab.syncad.com/hive/hivemind
      ```
    - Build **postgrest-rewriter**
      ```
      docker build -t postgrest_rewriter:local -f Dockerfile.rewriter .
      ```

### Deployment using The HAF API Node

Due to the complexity of setting up and syncing **HAF**, **reputation_tracker**,
and **Hivemind**, it is recommended to use the
[HAF API Node](https://gitlab.syncad.com/hive/haf_api_node). This is a
preconfigured Docker Compose setup that simplifies the full installation and
deployment of **Hivemind**, **HAF**, and **reputation_tracker**.

#### Choosing the Correct Version of Hivemind

To select the appropriate version of Hivemind, edit the `.env` file in the Docker
Compose configuration. Set the version for the variable `HIVE_API_NODE_VERSION`
to ensure that the HAF and its associated applications are correctly paired and
released together.

Alternatively, you can uncomment and set the specific variables affecting
Hivemind directly:

```bash
# Hivemind container registry and version
HIVEMIND_IMAGE            # Container registry for Hivemind images
HIVEMIND_VERSION          # Hivemind image version available in the registry
HIVEMIND_REWRITER_IMAGE   # Version of the Nginx rewriter image required by Hivemind

# Reputation Tracker container registry and version
REPUTATION_TRACKER_IMAGE  # Container registry for reputation_tracker images
REPUTATION_TRACKER_VERSION # reputation_tracker image version
```

Once the `.env` file is properly configured, navigate to the directory
containing the Docker Compose file and start the HAF API Node with the
following command:
```bash
docker compose up -d
```

This command pulls all the necessary images (e.g., HAF, reputation_tracker, Hivemind, etc.) and starts the containers 
in the required order based on the dependencies defined in the Docker Compose configuration.

#### Updating hivemind
When you want to update Hivemind to another version that is compatible with the current one,
meaning the database schema has not changed between versions, then:
1. Stop docker compose
    ```bash
    docker compose down
    ```
2. Change **HIVEMIND_VERSION** variable in the **.env** file to the hivemind version
3. Start docker compose
   ```bash
    docker compose up -d
   ```

### Deployment without HAF API Node
When for some reason You need to deploy hivemind without using HAF API Node then You
must start the containers in an specific order.

#### Start containers

You need to have a running **HAF** instance with the **reputation_tracker**  
installed. In the examples below, image names are based on locally built  
versions, as described earlier.

If you prefer to use images from public registries instead of locally built  
ones (see [here](#build-docker-images) ) , update the image tags accordingly.
For example:
    Instead of `registry.gitlab.syncad.com/hive/haf/instance:local`,
    you can replace it with a specific tag from the public registry, such as
    `registry.gitlab.syncad.com/hive/haf/instance:b7870f22`.

1. create docker network
    ```bash
    docker network create haf;
    ```
2. Start the HAF container. This process is somewhat complex due to the various settings that can be configured
   to tailor HAF to the expected performance, available resources, and desired security level. For detailed
   configuration options, refer to [the HAF documentation](https://gitlab.syncad.com/hive/haf/-/blob/develop/doc/HAF_Detailed_Deployment.md#building-and-deploying-haf-inside-a-docker-container). The example below demonstrates how to start HAF with its
   default configuration. In this setup, the database and other disk resources are stored within 
   the Docker container's filesystem. Additionally, the **PG_ACCESS** variable is used to override the container’s PostgreSQL
   configuration, granting database access to everyone on the network what simplifies setup but is not acceptable on production environment.
   If you want to stop HAF synchronization at a specific block (e.g., block 5,000,000),
   add the option `--stop-at-block=5000000` to the command below.
   ```bash
   docker run -d -e PG_ACCESS="host haf_block_log all 0.0.0.0/0 trust" --network=haf --name=haf registry.gitlab.syncad.com/hive/haf/minimal-instance:local; 
   ```
3. Install and start **reputation_tracker**. The example below use default configuration, if you want to stop reputation_tracker
   synchronization at a specific block (e.g., block 5,000,000), add the option --stop-at-block=5000000 to the command process_blocks.
   ```bash
   docker run --rm --network=haf --name=reptracker registry.gitlab.syncad.com/hive/reputation_tracker:local install_app
   docker run -d --network=haf --name=reptracker registry.gitlab.syncad.com/hive/reputation_tracker:local process_blocks
   ```

When HAF and reputation tracker were installed then hivemind may be started.

1. Setup hivemind on HAF database
   Administrative access to HAF is required.
   ```bash
   docker run --rm --network=haf --name=hivemind registry.gitlab.syncad.com/hive/hivemind/instance:local setup --database-admin-url=postgresql://haf_admin@haf:5432/haf_block_log
   ```
2. Start indexer
    If you want to stop hivemind synchronization at a specific block (e.g., block 5,000,000),
    add the option `--test-max-block=5000000` to the command below.
   ```bash
   docker run -d --network=haf --name=hivemind registry.gitlab.syncad.com/hive/hivemind/instance:local sync --database-url=postgresql://hivemind@haf/haf_block_log
   ```
3. Start server and rewriter when indexer reach head block or stop because reach indexer --test-max-block limit. 
   ```bash
   docker run --rm -d --network=haf --name=hivemind-postgrest-server registry.gitlab.syncad.com/hive/hivemind:local server --database-url=postgresql://hivemind@haf:5432/haf_block_log
   docker run --rm -d --network=haf -p 8080:80 --name=hivemind_rewriter postgrest_rewriter:local
   ```
   Now You cen verify the setup with send a query to the server which is available on host port 80:
   ```bash
   curl localhost:8080 -H "Content-Type: application/json" -d '{"id":6,"jsonrpc":"2.0","method":"hive.get_info","params":"{}"}'
   ```

All the steps above use the default options for setting up and running HAF and its applications. You can check 
the available configuration options by executing the commands with the --help flag. Some configurable options
include setting the database URL, defining the block after which synchronization should stop, adjusting resource limits ...

#### Update hivemind to a new version
1. Stop hivemind container using `docker stop` command:
    ```bash
    docker stop hivemind_rewriter;
    docker rm hivemind_rewriter;
    docker stop hivemind-postgrest-server;
    docker rm hivemind-postgrest-server;
    docker stop hivemind;
    docker rm hivemind;
    ```
2. Update hivemind version by running it docker image with option --upgrade-schema:
   ```bash 
   docker run --rm --network=haf --name=hivemind registry.gitlab.syncad.com/hive/hivemind/instance:newverison  --upgrade-schema --database-url=postgresql://hivemind@haf/haf_block_log
   ```
   
#### Uninstall hivemind from HAF database
Sometimes it is required to uninstall hivemind from HAF database and then
install again and start syncing from scratch:
1. Stop hivemind container using `docker stop` command:
    ```bash
    docker stop hivemind_rewriter;
    docker rm hivemind_rewriter;
    docker stop hivemind-postgrest-server;
    docker rm hivemind-postgrest-server;
    docker stop hivemind;
    docker rm hivemind;
    ```
2. Start hivemind container with running uninstall_app script. All Hivemind data collected
   in the HAF database will be removed.
   ```bash
   docker run --rm --network=haf --name=hivemind registry.gitlab.syncad.com/hive/hivemind/instance:local uninstall_app --database-admin-url=postgresql://haf_admin@haf:5432/haf_block_log
   ```
   

## Development on local host

Hivemind is currently being built with a focus on containerized deployment.  
Therefore, all system settings are encapsulated within the `Dockerfile` and  
scripts, which are executed starting from  
[docker_entrypoint.sh](./docker/docker_entrypoint.sh).

However, it is important to add a few words of explanation for developers,  
so they can better understand what happens under the hood of the Docker  
container.

Below, it will be explained how to install and run the Hivemind application  
directly on a host system, which is currently encapsulated within the  
container.

### Environment

- Python 3.10+ required
- Python dependencies: `pip >= 22.2.2` and `setuptools >= 63.1.0`
- Postgres 17+ recommended

#### Dependencies

- Ubuntu: `sudo apt-get install python3 python3-pip python3-venv ngnix`

### Installation

#### Prerequisites

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

#### PostgREST Installation

The Hivemind server requires PostgREST version 12.0.2 to be installed. Below is a snippet to accomplish this:

```bash
sudo apt-get remove postgrest
wget https://github.com/PostgREST/postgrest/releases/download/v12.0.2/postgrest-v12.0.2-linux-static-x64.tar.xz
tar -xf postgrest-v12.0.2-linux-static-x64.tar.xz
sudo mv postgrest /usr/local/bin/
```

You can verify the installation with:
```bash
postgrest --version
```

### Build and install the hivemind python package

You can install additional dependencies for testing, development etc.
All the dependencies are listed in the [`setup.cfg`](./setup.cfg) file under the `[options.extras_require]` section.
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

#### Installing openresty and ngnix rule
Nginx acts as a rewriter, redirecting all JSON-RPC 2.0 calls to the `/rpc/home` endpoint to maintain compatibility with
the previous system version. The recently introduced PostgREST supports REST API, while legacy JSON-RPC calls must still
be handled. Nginx ensures that incoming JSON-RPC requests are rewritten as parameters to the REST `/rpc/home/` endpoint.
There are plans to introduce a proper REST API for Hivemind in the future.
Using the rule:

```log
rewrite ^/(.*)$ /rpc/home break;
```
All URLs are rewritten to `/rpc/home`, where further request processing takes place, including the conversion from
JSON-RPC to SQL queries.

- Install openresty on host
   ```bash
       wget -qO - https://openresty.org/package/pubkey.gpg | sudo apt-key add -
       sudo add-apt-repository -y "deb http://openresty.org/package/ubuntu $(lsb_release -sc) main"
       sudo apt update
       sudo apt install -y openresty
       sudo cp docker/hivemind_nginx.conf.template /usr/local/openresty/nginx/conf/nginx.conf.template
       sudo cp rewrite_rules.conf /usr/local/openresty/nginx/conf/rewrite_rules.conf
       sudo bash -c 'sed -e "s|\${REWRITE_LOG}|$REWRITE_LOG|g" -e "s|hivemind-postgrest-server|localhost|g" /usr/local/openresty/nginx/conf/nginx.conf.template > /usr/local/openresty/nginx/conf/nginx.conf'
   ```

### Installing Hivemind in HAF

The Hivemind HAF application must be installed in the HAF database. To proceed, you need administrative access to the PostgreSQL database.

**Note**: All steps assume that your current working directory (PWD) is the root of the Hivemind Git repository.

---

1. **Set up Hivemind SQL Roles and Schema**
   Run the following script to add the necessary SQL roles and schema to the database:
   ```bash
   ./scripts/setup_postgres.sh --postgres-url=<postgres db url with HAF administrative access>
   ```

2. **Install the [**Reputation Tracker**](https://gitlab.syncad.com/hive/reputation_tracker/) HAF Application**
   Hivemind requires the Reputation Tracker application to be installed. If it's not already installed, execute the following script from the `reputation_tracker` submodule. Since Hivemind is an irreversible application, it's advisable to set up Reputation Tracker in the same way. Be sure to configure the `reputation_tracker` schema, as its name is required for the next steps.
   ```bash
   ./reputation_tracker/scripts/install_app.sh --postgres-url=<postgres db url with HAF administrative access> --schema=reptracker_app --is_forking="false"
   ```

3. **Install the Hivemind HAF Application**
   Finally, install the Hivemind application itself:
   ```bash
   ./scripts/install_app.sh --postgres-url=<postgres db url with HAF administrative access>
   ```

---

#### Installing Hivemind on a Locally Installed HAF with Default Configuration

If you have installed HAF on your local machine using the default configuration (e.g., a PostgreSQL instance running locally on `localhost`), you can use the following commands to set up Hivemind. This process includes all the steps mentioned above:

```bash
./scripts/setup_postgres.sh --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log
./reputation_tracker/scripts/install_app.sh --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log --schema=reptracker_app --is_forking="false"
./scripts/install_app.sh --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log
```


### Running Hivemind Indexer

Once Hivemind is installed in a HAF database, the indexer can be started. Assuming you are in the
Hivemind virtual environment, you can start the sync process, which runs the HAF application. You
need to pass the `reputation_tracker` schema along with the database URL:

```bash
hive sync --reptracker-schema-name=reptracker_app --database-url=<postgres url using role hivemind>
```

The Hivemind indexer begins collecting social data into its tables. You can interrupt the process at any time using `Ctrl+C`,
and restart it with the same command. The synchronization will resume from the block immediately following the last 
successfully synced block. This process continues until synchronization reaches the Hive head block (known as "live sync").

**Important**: Until synchronization reaches the Hive head block, Hivemind cannot be used effectively for testing.
This is because not all SQL indexes are created, and queries for social data will be slow. To allow testing before 
live sync is achieved, you can limit synchronization to a specific block number using the `--test-max-block` option.
This ensures the sync process stops at the specified block and creates all necessary indexes before exiting.

Example:
```bash
hive sync --reptracker-schema-name=reptracker_app --test-max-block=5000000 --database-url=<postgres url using role hivemind>
```

Additional options for the syncing process are available. You can view them with:
```bash
hive sync --help
```

### Running Hivemind Server
When indexer has entered live sync, or was stopped because of reach --test-max-block block, then You can start hivemind
server.

1. Server needs a working ngnix rewriter to start it. Please run openresty service:
   - When You have installed openresty on host:
      ```bash
      sudo /etc/init.d/openresty start
      ```
   - When You use prepared docker container (recommended):
      ```bash
      docker run -d --name hivemind-nginx-rewriter -p 80:80 hivemind-nginx
      ```
2. Start the hivemind server (in hivemind virtual environment):
   ```bash
   sudo ./scripts/start_postgrest.sh
   ```

At this point, the server is running, and you can query it on port 80. Here’s an example using curl:
```bash
  curl localhost:80 --header "Content-Type: application/json" --data '{"id": "cagdbc1", "method": "condenser_api.get_follow_count", "params": ["gtg"], "jsonrpc": "2.0"}'
```

### API Tests
During development the most important tests are running sync followed by start the server and then
run API tests. Below is a procedure to setup hivemind and run the tests. Two way are represented, one with
using docker containers and second run on host with using hivemind virtual environment.  

1. To got prepared setup in reasonable time for testing purpose is used HAF synchronized to 5M of blocks. HAF synchronization must be started
    with option `--stop-at-block=5000000`. HAF must remain running after synchronization is complete.
    For testing purposes, HAF must be synchronized from a block log containing at least 5 million blocks, not from
    the P2P network, because recent blocks would remain reversible. In the workplace-haf directory, a blockchain
    directory is created, and a block_log file (either split or monolithic) is copied into it.
    ```
    └── workplace-haf
        ├── blockchain
        │   └── block_log
    ```
   Enter to the hivemind sources directory and then create and docker network and start syncing HAF with passing path to `workplace-haf`
   as a variable DATADIR.
    ```bash
    docker network create haf;
    docker run -d -e PG_ACCESS="host haf_block_log all 0.0.0.0/0 trust" -e DATADIR=/home/hived/datadir -v /path/to/workpace-haf:/home/hived/datadir --shm-size=4294967296 --network=haf --name=haf registry.gitlab.syncad.com/hive/haf/minimal-instance:local --replay --stop-at-block=5000000
    ```

   You can observe the progress of synchronization with the command: `docker logs -n 100 -f haf`. Because the HAF must stay running
   after finishing synchronization, to check if it is ready for the next steps, look for a log entry like this::
   ```
   PROFILE: Entered LIVE sync from start state: 347 s 5000000
   ```
   Alternatively, a simpler way to verify readiness is to check if log output has stopped.
2. Five million blocks represent only the beginning of Hive's history. There is a lack of blocks
   containing operations that were added later for Hivemind, such as follow or communities. To test all Hivemind
   functions, we must inject operations into an already synced HAF instance.  
   Prepared scripts are available in the [mock_data folder](./mock_data) folder, which inject new virtual
   operations and blocks into the HAF database.
   
   - Preferred method to inject new data into HAF is to use dockerized hivemind setup together with *reputation_tracker*
      ```bash
      docker run --rm --network=haf --name=hivemind registry.gitlab.syncad.com/hive/hivemind/instance:local setup --database-admin-url=postgresql://haf_admin@haf:5432/haf_block_log --with-reptracker --add-mocks="true"
      ```
   - working in hivemind virtual environment on host:
     ```bash
     export MOCK_BLOCK_DATA_PATH="mock_data/block_data"
     export MOCK_VOPS_DATA_PATH="mock_data/vops_data"
     psql -d haf_block_log -f scripts/ci/wrapper_for_app_next_block.sql # to correctly stop on a 5M+24 block
     mocker --database-url=postgresql://haf_admin@localhost:5432/haf_block_log
     ```
3. Start syncing reputation_tracker to block 4,999,979. It must be synced to this block because
   Hivemind will complete its massive sync at this point and then begin collecting cache for notifications,
   which impacts the tests.
   - dockerized setup:
     ```bash
     docker run --rm --network=haf --name=hivemind --entrypoint=./app/reputation_tracker/scripts/process_blocks.sh registry.gitlab.syncad.com/hive/hivemind/instance:local --stop-at-block=4999979 --postgres-url="postgresql://haf_admin@haf/haf_block_log"
     ```
   - working in hivemind virtual environment on host:
     ```bash
     ./reputation_tracker/scripts/install_app.sh --postgres-url=postgresql://haf_admin@localhost:5432/haf_block_log --schema=reptracker_app --is_forking="false"
     ./reputation_tracker/scripts/process_blocks.sh --stop-at-block=4999979
     ```
4. Syncing Hivemind up to block 5,000,024 while testing which block the communities feature starts at.
   Communities normally start much later, well beyond 5 million blocks, so we need to pretend that they started earlier
   to enable support for them.
   - dockerized setup:
     ```bash
     docker run --rm --network=haf --name=hivemind registry.gitlab.syncad.com/hive/hivemind/instance:local sync --test-max-block=5000024 --community-start-block=4998000 --database-url=postgresql://hivemind@haf/haf_block_log
     ```
   - working in hivemind virtual environment on host:
     ```bash
     hive sync --reptracker-schema-name=reptracker_app --test-max-block=5000024 --community-start-block=4998000 --database-url=postgresql://hivemind@localhost:5432/haf_block_log
     ```
5. When hivemind in synced now reputation tracker must by synced up to 5,000,024:
   - dockerized setup:
     ```bash
     docker run --rm --network=haf --name=hivemind --entrypoint=./app/reputation_tracker/scripts/process_blocks.sh registry.gitlab.syncad.com/hive/hivemind/instance:local --stop-at-block=5000024 --postgres-url="postgresql://haf_admin@haf/haf_block_log"
     ```
   - working in hivemind virtual environment on host:
     ```bash
     ./reputation_tracker/scripts/process_blocks.sh --stop-at-block=5000024
     ```
6. Now we have all the data required by the tests, time to start hivemind server
   - dockerized setup
     ```bash
     docker run -d --network=haf --name=hivemind-postgrest-server registry.gitlab.syncad.com/hive/hivemind:local server --database-url=postgresql://hivemind@haf:5432/haf_block_log
     docker run -d --network=haf --name=hivemind_rewriter postgrest_rewriter:local
     ```
   - working in hivemind virtual environment on host:
     ```bash
     hive server --http-server-port=8080 --database-url=postgresql://hivemind@localhost:5432/haf_block_log
     ```
     and in parallel, in separate console start the rewriter process:
     ```bash
     sudo /etc/init.d/openresty start
     ```
7. Start the tests
  The test definitions are located in the [tests/api_tests/hivemind/tavern](tests/api_tests/hivemind/tavern) directory.
  They are written using the Tavern framework, which allows tests to be written in YAML and executed with pytest.
  You can start tests for any subfolder within `tests/api_tests/hivemind/tavern`
  - dockerized setup, must be run from host from the root of hivemind sources
    ```bash
    docker run --rm -v $(pwd):/home/hivemind/tests --network=haf --name=hivemind_tests --entrypoint=/bin/bash registry.gitlab.syncad.com/hive/hivemind/instance:local -c "cd /home/hivemind/tests;PATH=${PATH}:/home/hivemind/.local/bin ./scripts/run_tests.sh hivemind_rewriter 80 bridge_api_patterns/get_ranked_posts"
    ```
  - working in hivemind virtual environment on host:
    ```bash
    ./scripts/ci/start-api-smoketest.sh localhost 8080 bridge_api_patterns/get_ranked_posts/ api_smoketest_bridge.xml
    ```
#### Other methods of testing the API
- **Execute sql query** directly on HAF database by calling dispatcher function`hivemind_endpoints.home` using a PostgreSQL client like psql or pgadmin:
    ```
    select * from hivemind_endpoints.home('{"jsonrpc": "2.0", "id": 1, "method": "hive.get_info", "params": {}}'::json);
    ```
- **Send query with curl**
  ```
  curl localhost:8080 --header "Content-Type: application/json" --data '{"id": "cagdbc1", "method": "condenser_api.get_follow_count", "params": ["gtg"], "jsonrpc": "2.0"}'
  ```




