// Smoke test: quick sanity check that all API endpoints respond correctly.
// Runs 1 VU for 10s - use as a pre-check before heavier load tests.

import http from "k6/http";
import { check, sleep } from "k6";
import { BASE_URL, jsonRpc, headers, TEST_DATA } from "./config.js";

export const options = {
  vus: 1,
  duration: "10s",
  thresholds: {
    http_req_failed: ["rate==0"],
    http_req_duration: ["p(95)<5000"],
  },
};

const requests = [
  { method: "bridge.get_ranked_posts", params: { sort: "trending", tag: "", limit: 3 } },
  { method: "bridge.get_profile", params: { account: "gtg" } },
  { method: "bridge.get_post_header", params: { author: "gtg", permlink: "witness-gtg" } },
  { method: "bridge.get_trending_topics", params: {} },
  { method: "bridge.get_account_posts", params: { sort: "blog", account: "gtg", limit: 3 } },
  { method: "bridge.account_notifications", params: { account: "gtg", limit: 5 } },
  { method: "condenser_api.get_followers", params: ["gtg", "", "blog", 5] },
  { method: "condenser_api.get_following", params: ["gtg", "", "blog", 5] },
  { method: "condenser_api.get_follow_count", params: ["gtg"] },
  { method: "condenser_api.get_content", params: ["gtg", "witness-gtg"] },
  { method: "condenser_api.get_discussions_by_trending", params: [{ tag: "", limit: 3 }] },
  { method: "database_api.list_votes", params: { start: ["gtg", "witness-gtg", ""], limit: 5, order: "by_comment_voter" } },
  { method: "database_api.find_comments", params: { comments: [["gtg", "witness-gtg"]] } },
  { method: "hive.db_head_state", params: {} },
];

export default function () {
  for (const req of requests) {
    const res = http.post(BASE_URL + "/", jsonRpc(req.method, req.params), { headers });
    check(res, {
      [`${req.method} returns 200`]: (r) => r.status === 200,
      [`${req.method} valid jsonrpc`]: (r) => {
        try {
          return JSON.parse(r.body).jsonrpc === "2.0";
        } catch (e) {
          return false;
        }
      },
      [`${req.method} no error`]: (r) => {
        try {
          return !JSON.parse(r.body).error;
        } catch (e) {
          return false;
        }
      },
    });
    sleep(0.1);
  }
}
