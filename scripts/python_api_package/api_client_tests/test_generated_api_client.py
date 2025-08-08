from __future__ import annotations

from typing import Final

from api_client_tests.api_caller import HivemindApiCaller

from beekeepy._communication.url import HttpUrl

DEFAULT_ENDPOINT_FOR_TESTS: Final[HttpUrl] = HttpUrl("https://api.syncad.com")
SEARCHED_ACCOUNT_IN_TESTS: Final[str] = "gtg"

async def test_generated_api_client():
    # ARRANGE
    api_caller = HivemindApiCaller(endpoint_url=DEFAULT_ENDPOINT_FOR_TESTS)

    # ACT
    async with api_caller as api:
        result = await api.api.hivemind_api.accounts_operations(SEARCHED_ACCOUNT_IN_TESTS)

    # ASSERT
    assert isinstance(result.operations_result, list), "Expected operations_result to be a list"
    assert isinstance(result.total_operations, int), "Expected total_operations to be a int"
