"""Hive API: Public endpoints"""

import logging

from hive.conf import SCHEMA_NAME

log = logging.getLogger(__name__)


async def get_info(context):
    db = context['db']

    sql = f"SELECT MAX(num) FROM hive.{SCHEMA_NAME}_blocks_view;"
    database_head_block = await db.query_one(sql)

    sql = f"SELECT level, patch_date, patched_to_revision FROM {SCHEMA_NAME}.hive_db_patch_level ORDER BY level DESC LIMIT 1"
    patch_level_data = await db.query_row(sql)

    from hive.version import VERSION, GIT_REVISION, GIT_DATE

    ret = {
        "hivemind_version": VERSION,
        "hivemind_git_rev": GIT_REVISION,
        "hivemind_git_date": str(GIT_DATE),
        "database_schema_version": patch_level_data['level'],
        "database_patch_date": str(patch_level_data['patch_date']),
        "database_patched_to_revision": patch_level_data['patched_to_revision'],
        "database_head_block": database_head_block,
    }

    return ret
