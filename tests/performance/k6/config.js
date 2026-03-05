// Shared configuration for k6 performance tests

export const BASE_URL = __ENV.HIVEMIND_URL || "http://localhost:8080";

// Standard k6 options - override via CLI or environment
export const defaultOptions = {
  thresholds: {
    http_req_duration: ["p(95)<2000", "p(99)<5000"],
    http_req_failed: ["rate<0.01"],
  },
};

// JSON-RPC 2.0 request helper
let reqId = 0;
export function jsonRpc(method, params) {
  return JSON.stringify({
    jsonrpc: "2.0",
    id: ++reqId,
    method: method,
    params: params,
  });
}

export const headers = {
  "Content-Type": "application/json",
};

// Test accounts/data that exist in the 5M block test dataset
export const TEST_DATA = {
  accounts: ["gtg", "blocktrades", "steemit", "curie", "smooth"],
  authors: ["gtg", "blocktrades", "steemit"],
  permlinks: {
    gtg: "witness-gtg",
  },
  tags: ["hive", "polish", "photography", "life", "blog"],
  communities: ["hive-117600"],
};
