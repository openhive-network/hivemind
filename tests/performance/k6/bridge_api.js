import http from "k6/http";
import { check, group } from "k6";
import { Rate, Trend } from "k6/metrics";
import { BASE_URL, jsonRpc, headers, TEST_DATA, defaultOptions } from "./config.js";

const errorRate = new Rate("errors");
const bridgeDuration = new Trend("bridge_api_duration", true);

export const options = Object.assign({}, defaultOptions, {
  scenarios: {
    bridge_api: {
      executor: "ramping-vus",
      startVUs: 1,
      stages: [
        { duration: __ENV.RAMP_UP || "30s", target: parseInt(__ENV.VUS || "10") },
        { duration: __ENV.DURATION || "2m", target: parseInt(__ENV.VUS || "10") },
        { duration: __ENV.RAMP_DOWN || "10s", target: 0 },
      ],
    },
  },
});

export default function () {
  group("bridge.get_ranked_posts", () => {
    const sorts = ["trending", "hot", "created", "payout"];
    const sort = sorts[Math.floor(Math.random() * sorts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.get_ranked_posts", { sort: sort, tag: "", limit: 10 }),
      { headers }
    );
    check(res, { "ranked_posts 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });

  group("bridge.get_post_header", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.get_post_header", {
        author: "gtg",
        permlink: TEST_DATA.permlinks.gtg,
      }),
      { headers }
    );
    check(res, { "post_header 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });

  group("bridge.get_profile", () => {
    const account =
      TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.get_profile", { account: account }),
      { headers }
    );
    check(res, { "profile 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });

  group("bridge.get_account_posts", () => {
    const account =
      TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.get_account_posts", {
        sort: "blog",
        account: account,
        limit: 5,
      }),
      { headers }
    );
    check(res, { "account_posts 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });

  group("bridge.get_community", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.get_community", {
        name: TEST_DATA.communities[0],
      }),
      { headers }
    );
    check(res, { "community 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });

  group("bridge.get_trending_topics", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.get_trending_topics", {}),
      { headers }
    );
    check(res, { "trending_topics 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });

  group("bridge.account_notifications", () => {
    const account =
      TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.account_notifications", {
        account: account,
        limit: 10,
      }),
      { headers }
    );
    check(res, { "notifications 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });

  group("bridge.get_discussion", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("bridge.get_discussion", {
        author: "gtg",
        permlink: TEST_DATA.permlinks.gtg,
      }),
      { headers }
    );
    check(res, { "discussion 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    bridgeDuration.add(res.timings.duration);
  });
}
