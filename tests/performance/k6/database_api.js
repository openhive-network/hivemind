import http from "k6/http";
import { check, group } from "k6";
import { Rate, Trend } from "k6/metrics";
import { BASE_URL, jsonRpc, headers, defaultOptions } from "./config.js";

const errorRate = new Rate("errors");
const dbDuration = new Trend("database_api_duration", true);

export const options = Object.assign({}, defaultOptions, {
  scenarios: {
    database_api: {
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
  group("database_api.list_votes", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("database_api.list_votes", {
        start: ["gtg", "witness-gtg", ""],
        limit: 10,
        order: "by_comment_voter",
      }),
      { headers }
    );
    check(res, { "list_votes 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    dbDuration.add(res.timings.duration);
  });

  group("database_api.find_votes", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("database_api.find_votes", {
        author: "gtg",
        permlink: "witness-gtg",
      }),
      { headers }
    );
    check(res, { "find_votes 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    dbDuration.add(res.timings.duration);
  });

  group("database_api.find_comments", () => {
    const res = http.post(
      BASE_URL + "/",
      jsonRpc("database_api.find_comments", {
        comments: [["gtg", "witness-gtg"]],
      }),
      { headers }
    );
    check(res, { "find_comments 200": (r) => r.status === 200 });
    errorRate.add(res.status !== 200);
    dbDuration.add(res.timings.duration);
  });
}
