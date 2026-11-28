"""The JSON-RPC root answers each request with its id, of the type and value it was sent with."""

from typing import Any

import pytest
from rest_checks import service

_IDS = [1, 1.5, "abc", "1"]

_SUCCESSES = {
    "bridge": ("bridge.account_notifications", {"account": "alice", "limit": 1}),
    "condenser_api": ("condenser_api.get_follow_count", ["gtg"]),
    "database_api": ("database_api.find_comments", {"comments": []}),
}

_ERRORS = {
    "unknown method": {"method": "bridge.no_such_method", "params": {}},
    "invalid parameters": {"method": "condenser_api.get_follow_count", "params": {"account": "nonexisting"}},
    "missing method": {"params": {}},
    "missing params": {"method": "bridge.get_ranked_posts"},
}


def _answer(body: dict[str, Any]) -> dict[str, Any]:
    response = service.json_rpc_post({"jsonrpc": "2.0", **body})
    assert response.status_code == 200, f"{body} answered HTTP {response.status_code}: {response.text}"
    answer = response.json()
    assert isinstance(answer, dict), f"{body} answered no JSON object: {answer}"
    return answer


def _assert_same_id(answer: dict[str, Any], request_id: Any) -> None:
    assert "id" in answer, answer
    assert type(answer["id"]) is type(request_id) and answer["id"] == request_id, answer


@pytest.mark.parametrize("request_id", _IDS, ids=repr)
@pytest.mark.parametrize("call", _SUCCESSES.values(), ids=_SUCCESSES.keys())
def test_success_echoes_the_id(call: tuple[str, Any], request_id: Any) -> None:
    method, params = call
    answer = _answer({"id": request_id, "method": method, "params": params})
    assert "result" in answer and "error" not in answer, answer
    _assert_same_id(answer, request_id)


@pytest.mark.parametrize("request_id", _IDS, ids=repr)
@pytest.mark.parametrize("body", _ERRORS.values(), ids=_ERRORS.keys())
def test_error_echoes_the_id(body: dict[str, Any], request_id: Any) -> None:
    answer = _answer({"id": request_id, **body})
    assert "error" in answer and "result" not in answer, answer
    _assert_same_id(answer, request_id)


@pytest.mark.parametrize("body", [{}, {"id": None}], ids=["missing id", "null id"])
def test_without_an_id_id_is_required(body: dict[str, Any]) -> None:
    answer = _answer({**body, "method": "condenser_api.get_follow_count", "params": ["gtg"]})
    assert answer == {"id": None, "jsonrpc": "2.0", "error": "id required"}
