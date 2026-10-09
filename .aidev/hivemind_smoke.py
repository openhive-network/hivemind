#!/usr/bin/env python3
"""Serve the installed hivemind schema with PostgREST and check its API answers.

    hivemind_smoke.py OUT_DIR

Starts `postgrest` the way scripts/start_postgrest.sh does (schema
hivemind_endpoints, anonymous role hivemind) on a free loopback port, against
HIVEMIND_TEST_USER_URL, then makes the calls in CHECKS. JSON-RPC goes to
/rpc/home, where the postgrest-rewriter (rewrite_rules.conf) sends `/`. The
database is an empty HAF testnet one, so every check asserts the shape an empty
chain answers with (the testnet's genesis accounts exist, posts and communities
don't), not chain data.

Then runs the psql scripts in SQL_TESTS against the same database: they seed the
data they need in a transaction they roll back, and fail by raising.

Writes OUT_DIR/api-smoke.xml (one junit case per call or script) and exits
non-zero when any fails. To check another method or endpoint, add it to CHECKS.
"""
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
STARTUP_TIMEOUT_S = 60


def rpc(method, params):
    return ("POST", "/rpc/home", {"jsonrpc": "2.0", "method": method, "params": params, "id": 1})


def result_has(*keys):
    def check(status, body):
        assert status == 200, f"HTTP {status}"
        assert "error" not in body, f"error: {body.get('error')}"
        missing = [k for k in keys if k not in body["result"]]
        assert not missing, f"result lacks {missing}: {body['result']}"
    return check


def result_is(expected):
    def check(status, body):
        assert status == 200, f"HTTP {status}"
        assert body.get("result") == expected, f"result {body.get('result')!r}, expected {expected!r}"
    return check


def rpc_error(code):
    def check(status, body):
        assert status == 200, f"HTTP {status}"
        assert body.get("error", {}).get("code") == code, f"expected error {code}, got {body}"
    return check


def result_list():
    def check(status, body):
        assert status == 200, f"HTTP {status}"
        assert "error" not in body, f"error: {body.get('error')}"
        assert isinstance(body["result"], list), f"result is not a list: {body['result']!r}"
    return check


def http_json(kind):
    def check(status, body):
        assert status == 200, f"HTTP {status}"
        assert isinstance(body, kind), f"expected {kind.__name__}, got {body!r}"
    return check


# name, request, check(status, decoded body)
CHECKS = [
    ("jsonrpc/hive.db_head_state", rpc("hive.db_head_state", {}), result_has("db_head_block", "db_head_time", "db_head_age")),
    ("jsonrpc/hive.get_info", rpc("hive.get_info", {}), result_has("hivemind_version", "hivemind_git_rev", "database_head_block")),
    ("jsonrpc/condenser_api.get_follow_count", rpc("condenser_api.get_follow_count", ["initminer"]),
     result_is({"account": "initminer", "follower_count": 0, "following_count": 0})),
    ("jsonrpc/condenser_api.get_account_reputations", rpc("condenser_api.get_account_reputations", ["init", 1]),
     result_is([{"account": "initminer", "reputation": 0}])),
    ("jsonrpc/condenser_api.get_discussions_by_created", rpc("condenser_api.get_discussions_by_created", [{"limit": 5}]), result_is([])),
    ("jsonrpc/condenser_api.get_content.unknown", rpc("condenser_api.get_content", ["initminer", "nope"]), rpc_error(-32602)),
    ("jsonrpc/follow_api.get_followers", rpc("follow_api.get_followers", {"account": "initminer", "start": "", "type": "blog", "limit": 5}), result_is([])),
    ("jsonrpc/tags_api.get_discussion.unknown", rpc("tags_api.get_discussion", {"author": "initminer", "permlink": "nope"}), rpc_error(-32602)),
    ("jsonrpc/bridge.get_profile", rpc("bridge.get_profile", {"account": "initminer"}), result_has("id", "name", "stats", "metadata")),
    ("jsonrpc/bridge.get_ranked_posts", rpc("bridge.get_ranked_posts", {"sort": "trending", "limit": 5}), result_is([])),
    ("jsonrpc/bridge.get_ranked_posts_v2", rpc("bridge.get_ranked_posts_v2", {"sort": "trending", "limit": 5, "top_votes": 3}), result_is([])),
    ("jsonrpc/bridge.get_ranked_posts_v2.top_votes_11", rpc("bridge.get_ranked_posts_v2", {"sort": "trending", "top_votes": 11}), rpc_error(-32602)),
    ("jsonrpc/bridge.get_ranked_posts_v2.top_votes_negative", rpc("bridge.get_ranked_posts_v2", {"sort": "trending", "top_votes": -1}), rpc_error(-32602)),
    ("jsonrpc/bridge.get_ranked_posts_v2.extra_parameter", rpc("bridge.get_ranked_posts_v2", {"sort": "trending", "extra": 1}), rpc_error(-32602)),
    ("jsonrpc/bridge.get_ranked_posts.top_votes", rpc("bridge.get_ranked_posts", {"sort": "trending", "top_votes": 3}), rpc_error(-32602)),
    ("jsonrpc/bridge.get_account_posts_v2", rpc("bridge.get_account_posts_v2", {"sort": "posts", "account": "initminer"}), result_is([])),
    ("jsonrpc/bridge.get_post_v2.unknown", rpc("bridge.get_post_v2", {"author": "initminer", "permlink": "nope"}), rpc_error(-32602)),
    ("jsonrpc/bridge.get_discussion_v2.unknown", rpc("bridge.get_discussion_v2", {"author": "initminer", "permlink": "nope"}), rpc_error(-32602)),
    ("jsonrpc/bridge.list_votes.unknown", rpc("bridge.list_votes", {"author": "initminer", "permlink": "nope"}), rpc_error(-32602)),
    ("jsonrpc/bridge.list_communities", rpc("bridge.list_communities", {"limit": 5}), result_is([])),
    ("jsonrpc/bridge.get_trending_topics", rpc("bridge.get_trending_topics", {}), result_list()),
    ("jsonrpc/bridge.unread_notifications", rpc("bridge.unread_notifications", {"account": "initminer"}), result_has("unread", "lastread")),
    ("jsonrpc/bridge.get_community.unknown", rpc("bridge.get_community", {"name": "hive-123456"}), rpc_error(-32602)),
    ("jsonrpc/unknown_api", rpc("bridge_api.get_profile", {"account": "initminer"}), rpc_error(-32601)),
    ("jsonrpc/unknown_method", rpc("condenser_api.no_such_method", []), rpc_error(-32602)),
    ("rest/get_sync_status", ("GET", "/rpc/get_sync_status", None), http_json(dict)),
]

SQL_TESTS = [
    "tests/sql/bridge_vote_free_calls.sql",
]


def run_sql_test(path):
    proc = subprocess.run(
        ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", os.environ["HIVEMIND_TEST_USER_URL"], "-f", path],
        capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def call(base, request):
    method, path, payload = request
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base + path, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            status, raw = resp.status, resp.read()
    except urllib.error.HTTPError as err:
        status, raw = err.code, err.read()
    text = raw.decode("utf-8", "replace")
    try:
        return status, json.loads(text) if text.strip() else None, text
    except ValueError:
        return status, None, text


def wait_until_serving(base, proc, log_path):
    deadline = time.monotonic() + STARTUP_TIMEOUT_S
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"postgrest exited with {proc.returncode}; see {log_path}")
        try:
            if call(base, ("GET", "/rpc/get_sync_status", None))[0] == 200:
                return
        except OSError:
            pass
        time.sleep(1)
    raise RuntimeError(f"postgrest not serving after {STARTUP_TIMEOUT_S}s; see {log_path}")


def main(out):
    os.makedirs(out, exist_ok=True)
    port = free_port()
    base = f"http://127.0.0.1:{port}"
    log_path = os.path.join(out, "postgrest.log")
    env = dict(os.environ,
               PGRST_DB_URI=os.environ["HIVEMIND_TEST_USER_URL"],
               PGRST_DB_SCHEMAS="hivemind_endpoints",
               PGRST_DB_ANON_ROLE="hivemind",
               PGRST_SERVER_HOST="127.0.0.1",
               PGRST_SERVER_PORT=str(port))
    cases = os.path.join(out, "api-smoke.tsv")
    failed = 0
    with open(log_path, "w") as log, open(cases, "w") as tsv:
        proc = subprocess.Popen(["postgrest"], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            wait_until_serving(base, proc, log_path)
            for name, request, check in CHECKS:
                t0 = time.monotonic()
                status, body, text = call(base, request)
                try:
                    check(status, body)
                    verdict, message = "pass", ""
                    print(f"ok   {name}")
                except AssertionError as err:
                    failed += 1
                    verdict, message = "fail", str(err).replace("\t", " ").replace("\n", " ")[:300]
                    print(f"FAIL {name}: {message}\n     response: {text[:500]}")
                tsv.write(f"case\t{name}\t{verdict}\t{time.monotonic() - t0:.3f}\t{message}\n")
            for script in SQL_TESTS:
                t0 = time.monotonic()
                rc, output = run_sql_test(os.path.join(HERE, "..", script))
                if rc == 0:
                    verdict, message = "pass", ""
                    print(f"ok   sql/{script}\n{output}")
                else:
                    failed += 1
                    verdict, message = "fail", output.replace("\t", " ").replace("\n", " ")[-300:]
                    print(f"FAIL sql/{script}: exit {rc}\n{output[-2000:]}")
                tsv.write(f"case\tsql/{script}\t{verdict}\t{time.monotonic() - t0:.3f}\t{message}\n")
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
    subprocess.run([sys.executable, os.path.join(HERE, "junit_cases.py"), os.path.join(out, "api-smoke.xml"), "api-smoke", cases], check=True)
    total = len(CHECKS) + len(SQL_TESTS)
    print(f"{total - failed}/{total} calls and scripts answered as expected")
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} OUT_DIR")
    sys.exit(main(sys.argv[1]))
