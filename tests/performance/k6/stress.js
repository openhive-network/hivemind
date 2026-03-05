// Stress test: find the breaking point by ramping up to high concurrency.
// Reuses the mixed workload logic with aggressive scaling.

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";
import { BASE_URL, jsonRpc, headers, TEST_DATA, defaultOptions } from "./config.js";

const errorRate = new Rate("errors");
const requestDuration = new Trend("api_duration", true);

const MAX_VUS = parseInt(__ENV.MAX_VUS || "100");

export const options = Object.assign({}, defaultOptions, {
  thresholds: {
    http_req_duration: ["p(95)<10000"],
    errors: ["rate<0.10"],
  },
  scenarios: {
    stress: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: "1m", target: Math.round(MAX_VUS * 0.25) },
        { duration: "2m", target: Math.round(MAX_VUS * 0.5) },
        { duration: "2m", target: MAX_VUS },
        { duration: "2m", target: MAX_VUS },
        { duration: "1m", target: 0 },
      ],
    },
  },
});

function randomAccount() {
  return TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
}

const calls = [
  () =>
    jsonRpc("bridge.get_ranked_posts", {
      sort: ["trending", "hot", "created"][Math.floor(Math.random() * 3)],
      tag: "",
      limit: 10,
    }),
  () => jsonRpc("bridge.get_profile", { account: randomAccount() }),
  () =>
    jsonRpc("bridge.get_account_posts", {
      sort: "blog",
      account: randomAccount(),
      limit: 5,
    }),
  () =>
    jsonRpc("condenser_api.get_followers", [randomAccount(), "", "blog", 10]),
  () => jsonRpc("condenser_api.get_follow_count", [randomAccount()]),
  () =>
    jsonRpc("condenser_api.get_discussions_by_trending", [
      { tag: "", limit: 5 },
    ]),
  () =>
    jsonRpc("database_api.list_votes", {
      start: ["gtg", "witness-gtg", ""],
      limit: 10,
      order: "by_comment_voter",
    }),
  () => jsonRpc("hive.db_head_state", {}),
];

export default function () {
  const body = calls[Math.floor(Math.random() * calls.length)]();
  const res = http.post(BASE_URL + "/", body, { headers });

  check(res, { "status 200": (r) => r.status === 200 });
  errorRate.add(res.status !== 200);
  requestDuration.add(res.timings.duration);

  sleep(Math.random() * 0.3);
}
