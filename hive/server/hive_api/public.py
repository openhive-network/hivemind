"""Hive API: Public endpoints"""

import logging

log = logging.getLogger(__name__)

async def get_info(context):
    db = context['db']

    sql = "SELECT num FROM hive_blocks ORDER BY num DESC LIMIT 1"
    database_head_block = await db.query_one(sql)

    sql = "SELECT level, patch_date, patched_to_revision FROM hive_db_patch_level ORDER BY level DESC LIMIT 1"
    patch_level_data = await db.query_row(sql)

    from hive.version import VERSION, GIT_REVISION, GIT_DATE

    ret = {
        "hivemind_version" : VERSION,
        "hivemind_git_rev" : GIT_REVISION,
        "hivemind_git_date" : GIT_DATE,
        "database_schema_version" : patch_level_data['level'],
        "database_patch_date" : str(patch_level_data['patch_date']),
        "database_patched_to_revision" : patch_level_data['patched_to_revision'],
        "database_head_block" : database_head_block
    }

    return ret
