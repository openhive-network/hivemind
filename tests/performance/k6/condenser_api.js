import http from "k6/http";
import { check, group } from "k6";
import { Rate, Trend } from "k6/metrics";
import { BASE_URL, jsonRpc, headers, TEST_DATA, defaultOptions } from "./config.js";

const errorRate = new Rate("errors");
const condenserDuration = new Trend("condenser_api_duration", true);

export const options = Object.assign({}, defaultOptions, {
  scenarios: {
    condenser_api: {
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
  group("condenser_api.get_followers", () => {
    const account =
      TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_followers", [account, "", "blog", 10]),
      { headers }
    );
    check(res, { "followers 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_following", () => {
    const account =
      TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_following", [account, "", "blog", 10]),
      { headers }
    );
    check(res, { "following 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_follow_count", () => {
    const account =
      TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_follow_count", [account]),
      { headers }
    );
    check(res, { "follow_count 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_content", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_content", ["gtg", TEST_DATA.permlinks.gtg]),
      { headers }
    );
    check(res, { "content 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_content_replies", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_content_replies", [
        "gtg",
        TEST_DATA.permlinks.gtg,
      ]),
      { headers }
    );
    check(res, { "content_replies 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_discussions_by_trending", () => {
    const tag = TEST_DATA.tags[Math.floor(Math.random() * TEST_DATA.tags.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_discussions_by_trending", [
        { tag: tag, limit: 5 },
      ]),
      { headers }
    );
    check(res, { "discussions_trending 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_discussions_by_hot", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_discussions_by_hot", [{ tag: "", limit: 5 }]),
      { headers }
    );
    check(res, { "discussions_hot 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_blog", () => {
    const account =
      TEST_DATA.accounts[Math.floor(Math.random() * TEST_DATA.accounts.length)];
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_blog", [account, 0, 5]),
      { headers }
    );
    check(res, { "blog 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });

  group("condenser_api.get_account_reputations", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("condenser_api.get_account_reputations", ["gtg", 5]),
      { headers }
    );
    check(res, { "reputations 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    condenserDuration.add(res.timings.duration);
  });
}
