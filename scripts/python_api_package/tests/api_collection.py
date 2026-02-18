from __future__ import annotations

from beekeepy.handle.remote import AsyncSendable
from hiveio_hivemind_api.hivemind_api_client.hivemind_api_client import HivemindApi


class HivemindApiCollection:
    def __init__(self, owner: AsyncSendable) -> None:
        self.hivemind_api = HivemindApi(owner=owner)
