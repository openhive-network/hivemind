// Mixed workload simulating realistic API traffic patterns.
// Weights approximate real-world usage: bridge_api dominates, followed by
// condenser_api, with database_api and hive_api as lighter background traffic.

import http from "k6/http";
import { check, group, sleep } from "k6";
import { Rate, Trend, Counter } from "k6/metrics";
import { BASE_URL, jsonRpc, headers, TEST_DATA, defaultOptions } from "./config.js";

const errorRate = new Rate("errors");
const requestDuration = new Trend("api_duration", true);
const requestCount = new Counter("api_requests");

export const options = Object.assign({}, defaultOptions, {
  scenarios: {
    mixed: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: __ENV.RAMP_UP || "1m", target: parseInt(__ENV.VUS || "20") },
        { duration: __ENV.DURATION || "5m", target: parseInt(__ENV.VUS || "20") },
        { duration: __ENV.RAMP_DOWN || "30s", target: 0 },
      ],
    },
  },
});

// Weighted random selection
function weightedChoice(choices) {
  const total = choices.reduce((sum, c) => sum + c.weight, 0);
  let r = Math.random() * total;
  for (const c of choices) {
    r -= c.weight;
    if (r <= 0) return c.fn;
  }
  return choices[0].fn;
}

function randomAccount() {
  return TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
}

function randomTag() {
  return TEST_DATA.tags[Math.floor(Math.random() * TEST_DATA.tags.length)];
}

// --- Bridge API calls (60% of traffic) ---

function bridgeGetRankedPosts() {
  const sorts = ["trending", "hot", "created", "payout"];
  return http.post(
    BASE_URL + "/",
    jsonRpc("bridge.get_ranked_posts", {
      sort: sorts[Math.floor(Math.random() * sorts.length)],
      tag: "",
      limit: 10,
    }),
    { headers, tags: { api: "bridge", method: "get_ranked_posts" } }
  );
}

function bridgeGetProfile() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("bridge.get_profile", { account: randomAccount() }),
    { headers, tags: { api: "bridge", method: "get_profile" } }
  );
}

function bridgeGetAccountPosts() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("bridge.get_account_posts", {
      sort: "blog",
      account: randomAccount(),
      limit: 5,
    }),
    { headers, tags: { api: "bridge", method: "get_account_posts" } }
  );
}

function bridgeGetDiscussion() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("bridge.get_discussion", {
      author: "gtg",
      permlink: TEST_DATA.permlinks.gtg,
    }),
    { headers, tags: { api: "bridge", method: "get_discussion" } }
  );
}

function bridgeGetTrendingTopics() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("bridge.get_trending_topics", {}),
    { headers, tags: { api: "bridge", method: "get_trending_topics" } }
  );
}

function bridgeAccountNotifications() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("bridge.account_notifications", {
      account: randomAccount(),
      limit: 10,
    }),
    { headers, tags: { api: "bridge", method: "account_notifications" } }
  );
}

// --- Condenser API calls (25% of traffic) ---

function condenserGetFollowers() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("condenser_api.get_followers", [randomAccount(), "", "blog", 10]),
    { headers, tags: { api: "condenser", method: "get_followers" } }
  );
}

function condenserGetContent() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("condenser_api.get_content", ["gtg", TEST_DATA.permlinks.gtg]),
    { headers, tags: { api: "condenser", method: "get_content" } }
  );
}

function condenserGetDiscussionsTrending() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("condenser_api.get_discussions_by_trending", [
      { tag: randomTag(), limit: 5 },
    ]),
    { headers, tags: { api: "condenser", method: "get_discussions_by_trending" } }
  );
}

function condenserGetFollowCount() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("condenser_api.get_follow_count", [randomAccount()]),
    { headers, tags: { api: "condenser", method: "get_follow_count" } }
  );
}

// --- Database API calls (10% of traffic) ---

function dbListVotes() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("database_api.list_votes", {
      start: ["gtg", "witness-gtg", ""],
      limit: 10,
      order: "by_comment_voter",
    }),
    { headers, tags: { api: "database", method: "list_votes" } }
  );
}

function dbFindComments() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("database_api.find_comments", {
      comments: [["gtg", "witness-gtg"]],
    }),
    { headers, tags: { api: "database", method: "find_comments" } }
  );
}

// --- Hive API calls (5% of traffic) ---

function hiveDbHeadState() {
  return http.post(
    BASE_URL + "/",
    jsonRpc("hive.db_head_state", {}),
    { headers, tags: { api: "hive", method: "db_head_state" } }
  );
}

const endpoints = [
  // Bridge API - 60%
  { weight: 15, fn: bridgeGetRankedPosts },
  { weight: 12, fn: bridgeGetProfile },
  { weight: 12, fn: bridgeGetAccountPosts },
  { weight: 8, fn: bridgeGetDiscussion },
  { weight: 5, fn: bridgeGetTrendingTopics },
  { weight: 8, fn: bridgeAccountNotifications },
  // Condenser API - 25%
  { weight: 8, fn: condenserGetFollowers },
  { weight: 6, fn: condenserGetContent },
  { weight: 6, fn: condenserGetDiscussionsTrending },
  { weight: 5, fn: condenserGetFollowCount },
  // Database API - 10%
  { weight: 5, fn: dbListVotes },
  { weight: 5, fn: dbFindComments },
  // Hive API - 5%
  { weight: 5, fn: hiveDbHeadState },
];

export default function () {
  const callFn = weightedChoice(endpoints);
  const res = callFn();

  check(res, {
    "status is 200": (r) => r.status === 200,
    "has jsonrpc response": (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.jsonrpc === "2.0";
      } catch (e) {
        return false;
      }
    },
    "no error in response": (r) => {
      try {
        const body = JSON.parse(r.body);
        return !body.error;
      } catch (e) {
        return false;
      }
    },
  });

  errorRate.add(res.status !== 200);
  requestDuration.add(res.timings.duration);
  requestCount.add(1);

  // Brief pause between requests to simulate realistic user behavior
  sleep(Math.random() * 0.5);
}
