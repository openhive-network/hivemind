"""Hive API: Public endpoints"""

import logging

from hive.db.schema import DB_VERSION as SCHEMA_DB_VERSION

log = logging.getLogger(__name__)

async def get_info(context):
    db = context['db']

    sql = "SELECT num FROM hive_blocks ORDER BY num DESC LIMIT 1"
    database_head_block = await db.query_one(sql)

    from hive.version import VERSION, GIT_REVISION

    ret = {
        "hivemind_version" : VERSION,
        "hivemind_git_rev" : GIT_REVISION,
        "database_schema_version" : SCHEMA_DB_VERSION,
        "database_head_block" : database_head_block
    }

    return ret
