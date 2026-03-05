# Hivemind API Performance Tests

Load and performance tests for the Hivemind JSON-RPC API using [k6](https://k6.io/).

## Test Scenarios

| Script | Purpose | Default VUs | Default Duration |
|--------|---------|-------------|------------------|
| `k6/smoke.js` | Sanity check all endpoints | 1 | 10s |
| `k6/bridge_api.js` | Bridge API load test | 10 | 2m |
| `k6/condenser_api.js` | Condenser API load test | 10 | 2m |
| `k6/database_api.js` | Database API load test | 10 | 2m |
| `k6/mixed_workload.js` | Realistic mixed traffic | 20 | 5m |
| `k6/stress.js` | Find breaking point | up to 100 | 8m |

## Quick Start with Docker

The easiest way to run performance tests is with Docker Compose, which starts HAF, Hivemind server, and k6 together. This requires **pre-synced HAF data** (from CI cache or a local sync).

### Using the runner script

```bash
# Smoke test (default)
./tests/performance/run-perf-tests.sh --data-dir /path/to/synced/haf/datadir

# Mixed workload with 50 VUs for 10 minutes
./tests/performance/run-perf-tests.sh \
  --data-dir /path/to/synced/haf/datadir \
  --script mixed_workload.js \
  --vus 50 \
  --duration 10m

# Stress test
./tests/performance/run-perf-tests.sh \
  --data-dir /path/to/synced/haf/datadir \
  --script stress.js \
  --max-vus 200

# Keep services running after tests (for manual inspection)
./tests/performance/run-perf-tests.sh \
  --data-dir /path/to/synced/haf/datadir \
  --keep

# Tear down services from a previous --keep run
./tests/performance/run-perf-tests.sh --teardown

# Use CI-built images
./tests/performance/run-perf-tests.sh \
  --data-dir /path/to/synced/haf/datadir \
  --haf-image registry.gitlab.syncad.com/hive/haf/minimal-instance:develop \
  --hivemind-image registry.gitlab.syncad.com/hive/hivemind/instance:develop
```

### Using docker compose directly

```bash
cd tests/performance

# Start services
HAF_DATA_DIRECTORY=/path/to/synced/haf/datadir \
  docker compose up -d haf hivemind-server

# Wait for server to be ready, then run k6
K6_SCRIPT=smoke.js \
HAF_DATA_DIRECTORY=/path/to/synced/haf/datadir \
  docker compose run --rm k6

# Run a different test with custom settings
K6_SCRIPT=mixed_workload.js K6_VUS=30 K6_DURATION=5m \
HAF_DATA_DIRECTORY=/path/to/synced/haf/datadir \
  docker compose run --rm k6

# Tear down
HAF_DATA_DIRECTORY=/path/to/synced/haf/datadir \
  docker compose --profile test down -v
```

### Getting pre-synced HAF data

Performance tests need a HAF database synced to 5M blocks with Hivemind installed. Options:

**From CI cache (on builders with NFS access):**
```bash
# Find available caches
ssh hive-builder-10 'ls -lt /nfs/ci-cache/haf_hivemind_sync/*.tar | head -5'

# Extract to local directory
mkdir -p /tmp/haf_perf_data
tar xf /nfs/ci-cache/haf_hivemind_sync/<cache_key>.tar -C /tmp/haf_perf_data
```

**From a local sync (slow, ~1 hour):**
```bash
# Use the CI sync docker-compose
cd docker
HAF_IMAGE=registry.gitlab.syncad.com/hive/haf/minimal-instance:latest \
HIVEMIND_IMAGE=registry.gitlab.syncad.com/hive/hivemind/instance:latest \
HAF_DATADIR=/tmp/haf_perf_data/datadir \
HAF_SHM_DIR=/tmp/haf_perf_data/shm_dir \
  docker compose -f docker-compose-sync.yml up hivemind-setup
# Then start hivemind-sync after setup completes
```

## Running k6 Directly (without Docker)

If you already have a running Hivemind server, you can run k6 directly.

### Prerequisites

Install k6: https://grafana.com/docs/k6/latest/set-up/install-k6/

```bash
# Ubuntu/Debian
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D68
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6

# macOS
brew install k6
```

### Examples

```bash
# Quick smoke test against local server
k6 run tests/performance/k6/smoke.js

# Against a remote server
k6 run -e HIVEMIND_URL=http://my-server:8080 tests/performance/k6/smoke.js

# Bridge API with custom concurrency
k6 run -e VUS=25 -e DURATION=5m tests/performance/k6/bridge_api.js

# Mixed workload
k6 run -e VUS=50 -e DURATION=10m tests/performance/k6/mixed_workload.js

# Stress test
k6 run -e MAX_VUS=200 tests/performance/k6/stress.js

# Save results to JSON
k6 run --out json=results.json tests/performance/k6/mixed_workload.js
```

## CI Integration

To add performance tests to the CI pipeline, add a job after `e2e_benchmark_on_postgrest` that reuses the same services:

```yaml
perf_test:
  stage: benchmark
  needs:
    - sync
    - prepare_hivemind_image
    - find_haf_image
  image: grafana/k6:latest
  services:
    - name: ${HAF_IMAGE_NAME}
      alias: haf-instance
      entrypoint: ["/home/haf_admin/docker_entrypoint.sh", "--skip-hived"]
    - name: ${HIVEMIND_IMAGE}
      alias: hivemind-server
  variables:
    HIVEMIND_URL: http://hivemind-server:8080
  script:
    - k6 run tests/performance/k6/smoke.js
    - k6 run --out json=perf-results.json tests/performance/k6/mixed_workload.js
  artifacts:
    paths:
      - perf-results.json
    when: always
```

Alternatively, add a step to the existing `e2e_benchmark_on_postgrest` job's script section (after tavern tests pass) to run k6 against the already-running docker-compose services:

```bash
# Install k6 in the DinD runner
curl -fsSL https://dl.k6.io/key.gpg | gpg --dearmor -o /etc/apt/keyrings/k6.gpg
echo "deb [signed-by=/etc/apt/keyrings/k6.gpg] https://dl.k6.io/deb stable main" > /etc/apt/sources.list.d/k6.list
apt-get update && apt-get install -y k6

# Run against the already-running hivemind-server
k6 run -e HIVEMIND_URL=http://docker:8080 tests/performance/k6/mixed_workload.js
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HIVEMIND_URL` | `http://localhost:8080` | Target API URL |
| `VUS` | varies by test | Number of virtual users |
| `DURATION` | varies by test | Steady-state duration |
| `RAMP_UP` | `30s` | Ramp-up period |
| `RAMP_DOWN` | `10s` | Ramp-down period |
| `MAX_VUS` | `100` | Max VUs for stress test |

**Docker Compose variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `HAF_DATA_DIRECTORY` | (required) | Path to pre-synced HAF datadir |
| `HAF_IMAGE` | `registry.gitlab.syncad.com/hive/haf/minimal-instance:latest` | HAF Docker image |
| `HIVEMIND_IMAGE` | `registry.gitlab.syncad.com/hive/hivemind/instance:latest` | Hivemind Docker image |
| `HIVEMIND_PORT` | `8080` | API server port |
| `K6_SCRIPT` | `smoke.js` | k6 script to run |
| `K6_VUS` | `10` | Virtual users |
| `K6_DURATION` | `2m` | Test duration |
| `K6_MAX_VUS` | `100` | Max VUs (stress test) |

## Test Data

Tests use accounts and content from the 5M block test dataset (gtg, blocktrades, steemit, etc.). Edit `k6/config.js` to adjust test data for your environment.

## Interpreting Results

k6 outputs key metrics:
- **http_req_duration**: Response time (p50, p90, p95, p99)
- **http_req_failed**: Error rate
- **http_reqs**: Throughput (requests/sec)
- **errors**: Custom error rate tracking

Default thresholds:
- p95 response time < 2s (< 10s for stress test)
- Error rate < 1% (< 10% for stress test)
