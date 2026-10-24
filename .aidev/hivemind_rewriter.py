"""The postgrest-rewriter for the tavern step: rewrite_rules.conf in front of a PostgREST.

The runtime image has no nginx, so this interprets rewrite_rules.conf the way the rewriter
image's nginx applies it (docker/hivemind_nginx.conf.template): the rules in file order, the
first whose regex matches the path wins (each ends in `break`), `$N` is the Nth capture, and a
replacement with a query of its own gets the request's arguments appended to it. In front of
that it strips the `/hivemind-api` prefix the API node's reverse proxy removes, so the tests
can request the public URLs of the OpenAPI document. CI runs the rewriter image itself.
"""

import http.client
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit

PUBLIC_PREFIX = "/hivemind-api"
_RULE_RE = re.compile(r"rewrite\s+(\S+)\s+(\S+)\s+break;")
_CAPTURE_RE = re.compile(r"\$(\d)")
# Headers http.client sets itself or that describe one hop only.
_HOP_HEADERS = {"connection", "keep-alive", "transfer-encoding", "host", "content-length"}


def load_rules(text: str) -> list[tuple[re.Pattern[str], str]]:
    """The `rewrite REGEX REPLACEMENT break;` rules of rewrite_rules.conf, in order.

    Raises ValueError on any other directive, which this interpreter would not apply as nginx does.
    """
    rules = []
    for number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        match = _RULE_RE.fullmatch(line)
        if match is None:
            raise ValueError(f"rewrite_rules.conf:{number}: not a `rewrite REGEX REPLACEMENT break;` rule: {line}")
        rules.append((re.compile(match.group(1)), match.group(2)))
    return rules


def _substitute(match: re.Match[str], replacement: str) -> str:
    return _CAPTURE_RE.sub(lambda capture: match.group(int(capture.group(1))) or "", replacement)


def rewrite(rules: list[tuple[re.Pattern[str], str]], target: str) -> str:
    """The request target (path and query) nginx sends upstream for `target`."""
    split = urlsplit(target)
    path = unquote(split.path)
    if path == PUBLIC_PREFIX or path.startswith(PUBLIC_PREFIX + "/"):
        path = path[len(PUBLIC_PREFIX) :] or "/"
    for regex, replacement in rules:
        match = regex.search(path)
        if match is None:
            continue
        rewritten = _substitute(match, replacement)
        if "?" in rewritten:
            return f"{rewritten}&{split.query}" if split.query else rewritten
        return f"{rewritten}?{split.query}" if split.query else rewritten
    return f"{path}?{split.query}" if split.query else path


def start(rules_text: str, upstream_host: str, upstream_port: int, port: int) -> ThreadingHTTPServer:
    """Serves the rewriter on 127.0.0.1:`port` in a daemon thread; shut it down with .shutdown()."""
    rules = load_rules(rules_text)

    class Handler(BaseHTTPRequestHandler):
        def _proxy(self) -> None:
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            headers = {name: value for name, value in self.headers.items() if name.lower() not in _HOP_HEADERS}
            connection = http.client.HTTPConnection(upstream_host, upstream_port, timeout=120)
            try:
                connection.request(self.command, rewrite(rules, self.path), body=body or None, headers=headers)
                response = connection.getresponse()
                payload = response.read()
            finally:
                connection.close()
            self.send_response(response.status)
            for name, value in response.getheaders():
                if name.lower() not in _HOP_HEADERS:
                    self.send_header(name, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        do_GET = do_POST = _proxy

        def log_message(self, format: str, *args: object) -> None:
            pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
