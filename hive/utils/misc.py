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
    """Yield successive n-sized chunks from lst."""
    for i in range(0, len(lst), n):
        yield lst[i : i + n]


def show_app_version(log, database_head_block, patch_level_data):
    from hive.version import VERSION, GIT_REVISION, GIT_DATE

    log.info("hivemind_version : %s", VERSION)
    log.info("hivemind_git_rev : %s", GIT_REVISION)
    log.info("hivemind_git_date : %s", GIT_DATE)

    log.info("database_schema_version : %s", patch_level_data['level'])
    log.info("database_patch_date : %s", patch_level_data['patch_date'])
    log.info("database_patched_to_revision : %s", patch_level_data['patched_to_revision'])

    log.info("database_head_block : %s", database_head_block)


def get_memory_amount() -> float:
    """Returns memory amount in MB"""
    return round(psutil.virtual_memory().total / 1024.0 / 1024.0, 2)

