# Hivemind API Performance Tests

Load and performance tests for the Hivemind JSON-RPC API using [k6](https://k6.io/).

## Prerequisites

Install k6: https://grafana.com/docs/k6/latest/set-up/install-k6/

```bash
# Ubuntu/Debian
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D68
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6

# macOS
brew install k6

# Docker
docker run --rm -i grafana/k6 run - <script.js
```

## Test Scenarios

| Script | Purpose | Default VUs | Default Duration |
|--------|---------|-------------|------------------|
| `k6/smoke.js` | Sanity check all endpoints | 1 | 10s |
| `k6/bridge_api.js` | Bridge API load test | 10 | 2m |
| `k6/condenser_api.js` | Condenser API load test | 10 | 2m |
| `k6/database_api.js` | Database API load test | 10 | 2m |
| `k6/mixed_workload.js` | Realistic mixed traffic | 20 | 5m |
| `k6/stress.js` | Find breaking point | up to 100 | 8m |

## Running Tests

All tests default to `http://localhost:8080`. Override with `HIVEMIND_URL`.

```bash
# Quick smoke test
k6 run tests/performance/k6/smoke.js

# Against a specific server
k6 run -e HIVEMIND_URL=http://my-server:8080 tests/performance/k6/smoke.js

# Bridge API with custom concurrency and duration
k6 run -e VUS=25 -e DURATION=5m tests/performance/k6/bridge_api.js

# Mixed workload (realistic traffic simulation)
k6 run -e VUS=50 -e DURATION=10m tests/performance/k6/mixed_workload.js

# Stress test with custom max VUs
k6 run -e MAX_VUS=200 tests/performance/k6/stress.js

# Output results to JSON for analysis
k6 run --out json=results.json tests/performance/k6/mixed_workload.js
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
