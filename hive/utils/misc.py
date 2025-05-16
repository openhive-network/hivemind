from dataclasses import dataclass
from datetime import datetime
from logging import Logger
import os

import psutil

from hive.utils.stats import BroadcastObject, PrometheusClient


def log_memory_usage(memtypes=["rss", "vms", "shared"], broadcast=True) -> str:
    """
    Logs current memory types, additionally broadcast if broadcast set to True (default)

    Available memtypes: rss, vms, shared, text, lib, data, dirty
    """

    def format_bytes(val: int):
        assert isinstance(val, int) or isinstance(val, float), 'invalid data type, required int or float'
        return f'{val / 1024.0 / 1024.0 :.2f} MB'

    human_readable = {
        "rss": "physical_memory",
        "vms": "virtual_memory",
        "shared": "shared_memory",
        "text": "used_by_executable",
        "lib": "used_by_shared_libraries",
    }
    stats = psutil.Process(
        os.getpid()
    ).memory_info()  # docs: https://psutil.readthedocs.io/en/latest/#psutil.Process.memory_info
    if broadcast:
        PrometheusClient.broadcast(
            [BroadcastObject(f'hivemind_memory_{key}', getattr(stats, key), 'b') for key in stats._fields]
        )  # broadcast to prometheus
    return f"memory usage report: {', '.join([f'{human_readable.get(k, k)} = {format_bytes(getattr(stats, k))}' for k in memtypes])}"


def chunks(lst, n):
    """Yield successive n-sized chunks from list, dict, or set o."""
    if isinstance(lst, dict):
        items = list(lst.items())
        for i in range(0, len(items), n):
            yield dict(items[i:i + n])
    elif isinstance(lst, set):
        items = list(lst)
        for i in range(0, len(items), n):
            yield set(items[i:i + n])
    else:
        for i in range(0, len(lst), n):
            yield lst[i:i + n]


def get_memory_amount() -> float:
    """Returns memory amount in MB"""
    return round(psutil.virtual_memory().total / 1024.0 / 1024.0, 2)


@dataclass
class BlocksInfo:
    last: int
    last_imported: int
    last_completed: int


@dataclass
class PatchLevelInfo:
    level: int
    patch_date: datetime
    patched_to_revision: str


def show_app_version(log: Logger, blocks_info: BlocksInfo, patch_level_info: PatchLevelInfo):
    from hive.version import VERSION, GIT_REVISION, GIT_DATE

    log.info(f"hivemind_version : {VERSION}")
    log.info(f"hivemind_git_rev : {GIT_REVISION}")
    log.info(f"hivemind_git_date : {GIT_DATE}")

    log.info(f"database_schema_version : {patch_level_info.level}")
    log.info(f"database_patch_date : {patch_level_info.patch_date}")
    log.info(f"database_patched_to_revision : {patch_level_info.patched_to_revision}")

    log.info(f"last_block_from_view : {blocks_info.last}")
    log.info(f"last_imported_block : {blocks_info.last_imported}")
    log.info(f"last_completed_block : {blocks_info.last_completed}")
