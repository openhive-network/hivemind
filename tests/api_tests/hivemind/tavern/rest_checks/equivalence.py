"""REST tests derived from the JSON-RPC pattern tests of the methods REST endpoints wrap.

Every JSON-RPC tavern test of a wrapped method becomes a DerivedCase: either the REST request
that expresses the same call, checked against the JSON-RPC test's own .pat.json, or a skip
with the reason the call has no REST form. A JSON-RPC error maps to a PostgREST 400 carrying
the error's `message` (and its `data` as `details` when that is a string), which is what
hivemind_postgrest_utilities.raise_rest_exception produces.
"""

import os
import re
from collections import Counter
from collections.abc import Iterator
from dataclasses import dataclass, field
from typing import Any

import deepdiff
import yaml
from validate_response import PatternDiffException, load_pattern, predefined_ignore_tags, remove_tag, save_json

# The tavern directory: the JSON-RPC tests are read from it and their patterns compared with.
TAVERN_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEST_FILE_EXT = ".tavern.yaml"
PATTERN_FILE_EXT = ".pat.json"
RESPONSE_FILE_EXT = ".out.json"
# Responses that differ from the pattern are saved under this group, at the source test's path.
OUTPUT_DIR = "rest_api_equivalence"

_TEXT = "a text value"
_INT = "an integer"
_LIST = "a comma-separated list"


@dataclass(frozen=True)
class EndpointMapping:
    """A REST endpoint and the JSON-RPC method it wraps.

    `params` maps each JSON-RPC argument the endpoint can express to its REST parameter and
    that parameter's kind; `positional` is the method's argument order, as its
    validate_json_arguments template gives it, for calls with positional params; `required`
    the arguments whose REST parameter has no default. `rows` says the endpoint returns the
    method's list as rows (rest_json_rpc_rows), so a null list is an empty one.
    """

    endpoint: str
    method: str
    params: dict[str, tuple[str, str]]
    positional: tuple[str, ...]
    required: tuple[str, ...] = ()
    rows: bool = True


MAPPINGS: tuple[EndpointMapping, ...] = (
    EndpointMapping(
        "get_ranked_posts",
        "bridge.get_ranked_posts",
        {
            "sort": ("sort", _TEXT),
            "tag": ("tag", _TEXT),
            "limit": ("page-size", _INT),
            "start_author": ("start-author", _TEXT),
            "start_permlink": ("start-permlink", _TEXT),
            "observer": ("observer", _TEXT),
        },
        ("sort", "start_author", "start_permlink", "limit", "tag", "observer", "muted_reasons_filter", "truncate_body"),
    ),
    EndpointMapping(
        "get_account_posts",
        "bridge.get_account_posts",
        {
            "account": ("account-name", _TEXT),
            "sort": ("sort", _TEXT),
            "community": ("community", _TEXT),
            "limit": ("page-size", _INT),
            "start_author": ("start-author", _TEXT),
            "start_permlink": ("start-permlink", _TEXT),
            "observer": ("observer", _TEXT),
        },
        (
            "sort",
            "account",
            "start_author",
            "start_permlink",
            "limit",
            "observer",
            "truncate_body",
            "include_own",
            "community",
        ),
        required=("account",),
    ),
    EndpointMapping(
        "get_post",
        "bridge.get_post",
        {"author": ("author", _TEXT), "permlink": ("permlink", _TEXT), "observer": ("observer", _TEXT)},
        ("author", "permlink", "observer"),
        required=("author", "permlink"),
        rows=False,
    ),
    EndpointMapping(
        "get_account_profile",
        "bridge.get_profile",
        {"account": ("account-name", _TEXT), "observer": ("observer", _TEXT)},
        ("account", "observer"),
        required=("account",),
        rows=False,
    ),
    EndpointMapping(
        "get_account_followers",
        "condenser_api.get_followers",
        {
            "account": ("account-name", _TEXT),
            "start": ("start", _TEXT),
            "follow_type": ("type", _TEXT),
            "limit": ("page-size", _INT),
        },
        ("account", "start", "follow_type", "limit"),
        required=("account",),
    ),
    EndpointMapping(
        "get_account_following",
        "condenser_api.get_following",
        {
            "account": ("account-name", _TEXT),
            "start": ("start", _TEXT),
            "follow_type": ("type", _TEXT),
            "limit": ("page-size", _INT),
        },
        ("account", "start", "follow_type", "limit"),
        required=("account",),
    ),
    EndpointMapping(
        "get_account_notifications",
        "bridge.account_notifications",
        {
            "account": ("account-name", _TEXT),
            "type": ("type", _LIST),
            "community": ("community", _TEXT),
            "min_score": ("min-score", _INT),
            "limit": ("page-size", _INT),
            "last_id": ("last-id", _INT),
        },
        ("account", "min_score", "last_id", "limit", "type", "community"),
        required=("account",),
    ),
    EndpointMapping(
        "get_communities",
        "bridge.list_communities",
        {
            "sort": ("sort", _TEXT),
            "query": ("query", _TEXT),
            "limit": ("page-size", _INT),
            "last": ("last", _TEXT),
            "observer": ("observer", _TEXT),
        },
        ("last", "limit", "query", "sort", "observer"),
    ),
    EndpointMapping(
        "get_community",
        "bridge.get_community",
        {"name": ("name", _TEXT), "observer": ("observer", _TEXT)},
        ("name", "observer"),
        required=("name",),
        rows=False,
    ),
    EndpointMapping(
        "get_community_subscribers",
        "bridge.list_subscribers",
        {"community": ("name", _TEXT), "last": ("last", _TEXT), "limit": ("page-size", _INT)},
        ("community", "last", "limit"),
        required=("community",),
    ),
    EndpointMapping(
        "get_community_roles",
        "bridge.list_community_roles",
        {"community": ("name", _TEXT), "last": ("last", _TEXT), "limit": ("page-size", _INT)},
        ("community", "last", "limit"),
        required=("community",),
    ),
    EndpointMapping(
        "search_posts",
        "search-api.find_text",
        {
            "pattern": ("q", _TEXT),
            "sort": ("sort", _TEXT),
            "author": ("author", _TEXT),
            "limit": ("page-size", _INT),
            "start_author": ("start-author", _TEXT),
            "start_permlink": ("start-permlink", _TEXT),
            "observer": ("observer", _TEXT),
        },
        ("pattern", "sort", "author", "start_author", "start_permlink", "limit", "observer", "truncate_body"),
    ),
    EndpointMapping(
        "get_trending_tags",
        "bridge.get_trending_topics",
        {"limit": ("page-size", _INT), "observer": ("observer", _TEXT)},
        ("limit", "observer"),
    ),
)

_BY_METHOD = {mapping.method: mapping for mapping in MAPPINGS}


@dataclass(frozen=True)
class DerivedCase:
    """The REST form of one JSON-RPC test, or why it has none (`skip_reason`).

    `source` is the JSON-RPC test's path under the tavern directory, without its extension.
    `known_defect` names a defect of the REST surface the case is expected to fail on.
    """

    source: str
    mapping: EndpointMapping
    marks: tuple[str, ...] = ()
    rest_params: dict[str, str] = field(default_factory=dict)
    skip_reason: str | None = None
    error_response: bool = False
    ignore_tags: str | list[str] | None = None
    allow_null_response: bool = False
    numeric_tolerance: float | None = None
    known_defect: str | None = None


# PostgREST reads a GET argument whose value starts with an operator as a filter, so such a
# value (a valid Hive name like `not.existing`) never reaches the function.
_POSTGREST_OPERATOR_PREFIX = re.compile(
    r"^(eq|neq|gt|gte|lt|lte|like|ilike|match|imatch|in|is|isdistinct|fts|plfts|phfts|wfts"
    r"|cs|cd|ov|sl|sr|nxr|nxl|adj|not)\."
)


class _Unmappable(Exception):
    """The JSON-RPC call has no REST form; the message says why."""


@dataclass(frozen=True)
class _Tagged:
    tag: str


# Loads a tavern file, keeping each tavern YAML tag (!include, !int, …) as a _Tagged value. A
# SafeLoader subclass of its own, so the constructor does not change yaml.SafeLoader itself.
_TavernLoader: Any = type("_TavernLoader", (yaml.SafeLoader,), {})
_TavernLoader.add_multi_constructor("!", lambda loader, suffix, node: _Tagged("!" + suffix))


def _json_type(value: Any) -> str:
    if isinstance(value, bool):
        return "a boolean"
    if isinstance(value, int | float):
        return "a number"
    if isinstance(value, str):
        return "a string"
    if isinstance(value, list):
        return "an array"
    if isinstance(value, dict):
        return "an object"
    return "null"


def _rest_value(arg: str, value: Any, rest_param: str, kind: str) -> str:
    if isinstance(value, _Tagged):
        raise _Unmappable(f"argument {arg} is the tavern expression {value.tag}")
    if kind == _TEXT and isinstance(value, str):
        if "\x00" in value:
            raise _Unmappable(f"argument {arg} contains a NUL byte, which a REST text parameter cannot carry")
        return value
    if kind == _INT and isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if kind == _LIST and isinstance(value, list) and all(isinstance(item, str) and "," not in item for item in value):
        return ",".join(value)
    raise _Unmappable(f"argument {arg} is {_json_type(value)}; REST parameter {rest_param} takes {kind}")


def _named_args(mapping: EndpointMapping, params: Any) -> dict[str, Any]:
    if isinstance(params, list) and len(params) == 1 and isinstance(params[0], dict):
        params = params[0]
    if isinstance(params, dict):
        return params
    if isinstance(params, list):
        if len(params) > len(mapping.positional):
            raise _Unmappable(
                f"passes {len(params)} positional arguments; {mapping.method} takes {len(mapping.positional)}"
            )
        return dict(zip(mapping.positional, params, strict=False))
    raise _Unmappable(f"params is {_json_type(params)}")


def _rest_params(mapping: EndpointMapping, params: Any) -> dict[str, str]:
    """The REST query parameters expressing JSON-RPC `params` of `mapping.method`.

    A null argument is left out: the endpoint passes an absent parameter on as an absent
    argument. Raises _Unmappable naming the first argument with no REST form.
    """
    rest = {}
    args = _named_args(mapping, params)
    for arg in mapping.required:
        if args.get(arg) is None:
            raise _Unmappable(f"omits argument {arg}, which REST requires as {mapping.params[arg][0]}")
    for arg, value in args.items():
        if arg not in mapping.params:
            raise _Unmappable(f"argument {arg} has no REST parameter")
        if value is None:
            continue
        rest_param, kind = mapping.params[arg]
        rest[rest_param] = _rest_value(arg, value, rest_param, kind)
    return rest


def _called_method(request_json: Any) -> tuple[str | None, Any]:
    if not isinstance(request_json, dict):
        return None, None
    method, params = request_json.get("method"), request_json.get("params")
    if (
        method == "call"
        and isinstance(params, list)
        and len(params) == 3
        and all(isinstance(p, str) for p in params[:2])
    ):
        return f"{params[0]}.{params[1]}", params[2]
    return method, params


def _derive(source: str, document: dict[str, Any]) -> DerivedCase | None:
    stages = document.get("stages") or []
    request_json = stages[0].get("request", {}).get("json") if stages else None
    method, params = _called_method(request_json)
    mapping = _BY_METHOD.get(method) if isinstance(method, str) else None
    if mapping is None:
        return None
    marks = tuple(mark for mark in document.get("marks") or [] if isinstance(mark, str))
    case = DerivedCase(source, mapping, marks)
    if len(stages) != 1:
        return _skipped(case, f"has {len(stages)} stages")
    response = stages[0].get("response", {})
    if response.get("status_code") != 200:
        return _skipped(case, f"expects HTTP status {response.get('status_code')}")
    verify = response.get("verify_response_with") or {}
    if verify.get("function") != "validate_response:compare_response_with_pattern":
        return _skipped(case, f"is checked by {verify.get('function')}, not against an expected output")
    kwargs = verify.get("extra_kwargs") or {}
    try:
        rest_params = _rest_params(mapping, params)
    except _Unmappable as err:
        return _skipped(case, str(err))
    operator_values = sorted(name for name, value in rest_params.items() if _POSTGREST_OPERATOR_PREFIX.match(value))
    return DerivedCase(
        source,
        mapping,
        marks,
        rest_params,
        known_defect=(
            f"PostgREST reads the value of {', '.join(operator_values)} as a filter operator"
            if operator_values
            else None
        ),
        error_response=bool(kwargs.get("error_response", False)),
        ignore_tags=kwargs.get("ignore_tags"),
        allow_null_response=bool(kwargs.get("allow_null_response", False)),
        numeric_tolerance=kwargs.get("numeric_tolerance"),
    )


def _skipped(case: DerivedCase, reason: str) -> DerivedCase:
    return DerivedCase(case.source, case.mapping, case.marks, skip_reason=reason)


def _source_files(tavern_dir: str) -> Iterator[str]:
    names = tuple(mapping.method.split(".", 1)[1] for mapping in MAPPINGS)
    for directory, subdirs, files in os.walk(tavern_dir):
        subdirs.sort()
        for name in sorted(files):
            if not name.endswith(TEST_FILE_EXT):
                continue
            path = os.path.join(directory, name)
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            # Parsing every tavern file is the slow part of collection: only parse candidates.
            if any(method_name in text for method_name in names):
                yield path


def derive_cases(tavern_dir: str) -> list[DerivedCase]:
    """One DerivedCase per JSON-RPC tavern test under `tavern_dir` of a method in MAPPINGS."""
    cases = []
    for path in _source_files(tavern_dir):
        with open(path, encoding="utf-8") as handle:
            document = yaml.load(handle, Loader=_TavernLoader)
        source = os.path.relpath(path, tavern_dir)[: -len(TEST_FILE_EXT)]
        case = _derive(source, document) if isinstance(document, dict) else None
        if case is not None:
            cases.append(case)
    return cases


def coverage(cases: list[DerivedCase]) -> list[str]:
    """One line per mapping: how many of its JSON-RPC tests are mapped and how many skipped, then why."""
    lines = []
    for mapping in MAPPINGS:
        own = [case for case in cases if case.mapping is mapping]
        reasons = Counter(case.skip_reason for case in own if case.skip_reason is not None)
        skipped = sum(reasons.values())
        lines.append(f"{mapping.endpoint} <- {mapping.method}: {len(own) - skipped} mapped, {skipped} skipped")
        lines.extend(f"    skipped {count}: {reason}" for reason, count in sorted(reasons.items()))
        defects = Counter(case.known_defect for case in own if case.known_defect is not None)
        lines.extend(f"    expected to fail {count}: {defect}" for defect, count in sorted(defects.items()))
    return lines


def _fail(message: str, output_path: str, body: Any) -> None:
    save_json(output_path, body)
    raise PatternDiffException(f"{message}\nREST response: {output_path}")


def check_response(case: DerivedCase, status: int, body: Any, tavern_dir: str) -> None:
    """Checks a REST response to `case.rest_params` against the JSON-RPC test's expected output.

    Raises PatternDiffException, after saving the response under OUTPUT_DIR, when it differs.
    """
    pattern_path = os.path.join(tavern_dir, case.source + PATTERN_FILE_EXT)
    output_path = os.path.join(tavern_dir, OUTPUT_DIR, case.source + RESPONSE_FILE_EXT)
    if os.path.exists(output_path):
        os.remove(output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    pattern = load_pattern(pattern_path)

    if case.error_response:
        if status != 400 or not isinstance(body, dict) or not {"code", "details", "hint", "message"} <= body.keys():
            _fail(f"HTTP {status}: a PostgREST error was expected, as {pattern_path} is an error", output_path, body)
        data = pattern.get("data") if isinstance(pattern, dict) else None
        expected = {
            "message": pattern.get("message") if isinstance(pattern, dict) else None,
            "details": data if isinstance(data, str) else None,
        }
        actual = {"message": body["message"], "details": body["details"]}
        if expected != actual:
            _fail(f"the error differs from {pattern_path}: expected {expected}, got {actual}", output_path, body)
        return

    if status != 200:
        _fail(f"HTTP {status}: a result was expected, as in {pattern_path}", output_path, body)
    if body is None and not case.allow_null_response:
        _fail("the result is null, a JSON value was expected", output_path, body)
    if pattern is None and case.allow_null_response and case.mapping.rows:
        pattern = []
    if pattern is None:
        if body is not None:
            _fail(f"pattern {pattern_path} is missing", output_path, body)
        return
    result = body
    kwargs: dict[str, Any] = {}
    if isinstance(case.ignore_tags, str):
        kwargs["exclude_regex_paths"] = [predefined_ignore_tags[case.ignore_tags]]
    elif case.ignore_tags is not None:
        pattern, result = remove_tag(pattern, case.ignore_tags), remove_tag(result, case.ignore_tags)
    if case.numeric_tolerance is not None:
        kwargs["math_epsilon"] = case.numeric_tolerance
    diff = deepdiff.DeepDiff(pattern, result, **kwargs)
    if diff:
        lines = diff.to_json(indent=2).split("\n")
        _fail(f"the result differs from {pattern_path}:\n" + "\n".join(lines[:20]), output_path, body)
