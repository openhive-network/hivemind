"""Each REST endpoint wrapping a JSON-RPC method, over that method's JSON-RPC tests (see conftest.py)."""

from rest_checks import service
from rest_checks.equivalence import TAVERN_DIR, DerivedCase, check_response


def test_rest_matches_json_rpc_pattern(derived_case: DerivedCase) -> None:
    response = service.rest_rpc(derived_case.mapping.endpoint, derived_case.rest_params)
    check_response(derived_case, response.status_code, response.json(), TAVERN_DIR)
