import logging

from hive.conf import ONE_WEEK_IN_BLOCKS, REPTRACKER_SCHEMA_NAME, SCHEMA_NAME
from hive.db.adapter import Db

log = logging.getLogger(__name__)

# Custom JSON types that Hivemind processes
HIVEMIND_CUSTOM_JSON_TYPES = ['follow', 'reblog', 'community', 'notify']


def prepare_app_context(db: Db) -> None:
    log.info(f"Looking for '{SCHEMA_NAME}' and '{REPTRACKER_SCHEMA_NAME}' contexts.")
    ctx_present = db.query_one(f"SELECT hive.app_context_exists('{SCHEMA_NAME}') as ctx_present;")
    if not ctx_present:
        LIMIT_FOR_PROCESSED_BLOCKS = 1000
        synchronization_stages = f"""ARRAY[
              hive.stage( 'MASSIVE_WITHOUT_INDEXES', {ONE_WEEK_IN_BLOCKS}, {LIMIT_FOR_PROCESSED_BLOCKS}, '20 seconds' )
            , hive.stage( 'MASSIVE_WITH_INDEXES', 101, {LIMIT_FOR_PROCESSED_BLOCKS}, '20 seconds' )
            , hive.live_stage()
        ]::hive.application_stages"""
        log.info(f"No application context present. Attempting to create a '{SCHEMA_NAME}' context...")
        db.query_no_return(
            f"SELECT hive.app_create_context('{SCHEMA_NAME}', '{SCHEMA_NAME}', _is_forking => FALSE, _stages => {synchronization_stages} );"
        )  # is-forking=FALSE, only process irreversible blocks
        log.info("Application context creation done.")
    else:
        log.info("Found existing context, set to non-forking.")
        db.query_no_return(
            f"SELECT hive.app_context_set_non_forking('{SCHEMA_NAME}');"
        )  # if existing context, make it non-forking
        is_forking = db.query_one(f"SELECT hive.app_is_forking('{SCHEMA_NAME}') as is_forking;")
        log.info(f"is_forking={is_forking}")

    # Note: custom_json_type index creation is deferred to sync startup
    # (SyncHiveDb.run) so that the install container finishes quickly.


def ensure_custom_json_type_index(db: Db) -> None:
    """Register partial index on hafd.operations for Hivemind's custom_json types.

    Uses hive.register_index_dependency so HAF's indexes_controler creates the
    index with CREATE INDEX CONCURRENTLY, avoiding ShareLock contention with
    other apps that are writing to hafd.operations concurrently.
    """
    types_sql = ",".join(f"'{t}'" for t in HIVEMIND_CUSTOM_JSON_TYPES)

    # Look up numeric IDs for our custom_json types
    type_ids = db.query_all(
        f"SELECT id FROM hafd.custom_json_types "
        f"WHERE custom_json_id IN ({types_sql}) ORDER BY id"
    )
    if not type_ids:
        log.warning(f"No custom_json_type_ids found for {HIVEMIND_CUSTOM_JSON_TYPES} — index skipped")
        return

    ids = [row[0] for row in type_ids]
    index_name = 'hive_operations_custom_json_types_' + '_'.join(str(i) for i in ids) + '_idx'
    where_clause = 'custom_json_type_id IN (' + ','.join(str(i) for i in ids) + ')'
    create_cmd = f'CREATE INDEX IF NOT EXISTS {index_name} ON hafd.operations (custom_json_type_id) WHERE {where_clause}'

    log.info(f"Registering custom_json_type index dependency: {index_name}")
    db.query_no_return(
        f"SELECT hive.register_index_dependency('{SCHEMA_NAME}', $cmd${create_cmd}$cmd$);"
    )
