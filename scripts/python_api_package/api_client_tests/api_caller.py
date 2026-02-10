from __future__ import annotations

from beekeepy.handle.remote import AbstractAsyncHandle, AsyncBatchHandle, RemoteHandleSettings
from beekeepy.handle.runnable import RunnableHandleSettings
from beekeepy.interfaces import HttpUrl

from api_client_tests.api_collection import HivemindApiCollection


class HivemindApiCaller(AbstractAsyncHandle[RemoteHandleSettings, HivemindApiCollection]):
    def __init__(self, endpoint_url: HttpUrl) -> None:
        settings = RunnableHandleSettings()
        settings.http_endpoint = endpoint_url
        super().__init__(settings=settings)

    @property
    def api(self) -> HivemindApiCollection:
        return super().api

    async def batch(self, *, delay_error_on_data_access: bool = False) -> AsyncBatchHandle[HivemindApiCollection]:
        return AsyncBatchHandle(
            url=self.http_endpoint,
            overseer=self._overseer,
            api=lambda owner: HivemindApiCollection(owner=owner),
            delay_error_on_data_access=delay_error_on_data_access,
        )

    def _construct_api(self) -> HivemindApiCollection:
        return HivemindApiCollection(owner=self)

    def _target_service(self) -> str:
        return "hived"
